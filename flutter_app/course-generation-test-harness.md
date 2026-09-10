# Adaptive Course generation and release runbook

Last reviewed: 2026-09-08

This document is the source of truth for verifying the six Course lanes from
local tests through a real Debug device run and into a Release build. It
describes the current implementation; it is not a second lesson engine.

## The course contract

Every learner has one adaptive plan. The route is deterministic in shape and
personalized in content:

| Sequence | Meaning | Generation |
| ---: | --- | --- |
| 1–5 | Unit 1 sound foundation | Authored, ready locally |
| 6–11 | Unit 2: Vocabulary → Reading → Listening → Writing → Speaking → Grammar | Authored, ready locally |
| 12+ | Repeating six-session units in the same order | One validated AI artifact at a time |

`AdaptiveCourseStore` uses a six-row block after sequence 5. For a generated
unit, position 1 is Vocabulary, 2 Reading, 3 Listening, 4 Writing, 5 Speaking,
and 6 Grammar. The unit number is derived from the sequence; it is not chosen
by the learner's recent skill or by a random topic.

The 50/50 learning mix means roughly half recently useful words/patterns and
half new words/patterns. It does **not** mean that the previous story setting
is reused. The persisted session `context` is the authoritative unit anchor;
recent targets are retrieval evidence only. This is what allows a ticket
context to move from a train to a bus, car, concert, office, or another useful
scene without losing vocabulary continuity.

## What is persisted

The local SQLite database and Supabase are mirrors of the same contract.

- `adaptive_course_plans` stores the learner plan, level (`A1`–`B2`), goal,
  profile fingerprint, version, and `active`/`replaced` status.
- `adaptive_course_sessions` stores the ordered specification and the
  complete prepared artifact. The unique `(plan_id, sequence)` key prevents
  duplicate positions.
- `status` is the learner lifecycle: `planned → active → completed` (or
  `replaced`).
- `generation_status` is the preparation lifecycle:
  `queued → generating → ready`, or `failed`.
- `generation_attempts` and `generation_error` make a failure durable and
  inspectable. A failed row never hides or overwrites a ready row.

The client hydrates remote state before deciding whether to prepare anything.
This prevents a stale local snapshot from displaying “waiting” forever or
from regressing a remote ready artifact back to `queued`.

## One completion-to-next-lesson path

The same path is used in Debug and Release; the Debug harness only adds a
skill filter and an automatic completion trigger.

```text
finish activity
  → activity returns completion (bool; Grammar returns GrammarCourseSessionResult)
  → SpeakRoadmap marks the exact content key completed
  → AdaptiveCourseStore ensures the next ordered row exists locally
  → SyncService upserts the plan/session row to Supabase
  → prepare-course-lesson claims one queued row
  → Edge Function calls ai-text, validates the JSON, and saves the artifact
  → client hydrates the ready row
  → roadmap opens the newly ready lesson (Debug hand-off only)
```

In Release, completion is the preparation trigger: the next ordered row is
created, persisted, and prepared automatically after the learner finishes.
Opening a ready lesson, changing tabs, or replaying cached content never calls
the model. If a completion was interrupted by a background/force-quit, the
next roadmap foreground pass safely resumes the same queued row. In the Debug
harness, completing the selected lane's Unit 2 gate invokes the same path and
can open the newly ready row automatically.

## Edge Function: responsibility and limits

`flutter_app/supabase/functions/prepare-course-lesson/index.ts` is the secure
server boundary. The app sends an authenticated request; the function checks
the user, selects the newest active plan, and never accepts a plan belonging
to another user. Provider credentials stay server-side.

For each invocation it:

1. Recovers a `generating` row older than five minutes to `queued`.
2. Ignores authored sequences 1–11 and only considers generated sequences
   12+.
3. Filters by the Debug `harness_skill` when present; Release omits it.
4. Claims the oldest eligible row with a guarded status update. If another
   request won the claim, it returns a conflict instead of generating twice.
5. Calls `ai-text` using the existing OpenRouter text route, then validates
   the exact skill schema and CEFR level before saving `ready` content.
6. Writes a bounded error to the row and returns `failed` when preparation
   cannot complete.

The function does not fan out a batch. The Flutter client clamps
`maxLessons` to one and also coalesces an in-flight preparation request. A
single invocation allows at most two model attempts (the second is a repair
turn containing the validator error). A failed row can be claimed once more
when `generation_attempts < 2`; the Debug harness may requeue that one failed
row exactly once. Thus a normal success costs one provider attempt, while a
malformed artifact can use up to two attempts per claim and two claims in the
worst case. There is no timer-driven retry loop.

The remote `prepare-course-lesson` function is verified active at version 42
on 2026-09-09. It includes the Grammar whitelist, the authored boundary of
11, and the checked-in Guided blank-choice contract. If a Grammar row is stuck
in `queued`, verify the deployed version before changing client code.

### Quotas and scale

#### Grammar interaction contract

Course Grammar is currently Guided for every CEFR band (A1, A2, B1, and B2).
Each generated session must contain five steps; every step has one `___` blank,
three unique visible French forms, and a matching answer. The Complete
word-bank workshop and Roleplay remain Practice-only. The client rejects an old
or mismatched Complete artifact instead of opening it as Course content, and
generation contract version 7 requeues unfinished rows created by the previous
alternating mode.

The Edge Function runtime does not grant a universal Gemini/OpenRouter quota.
The effective limits are the Supabase project limits and the configured
provider/account limits, which can change. The app therefore enforces a
bounded per-user flow instead of guessing a quota in code:

- one client preparation future at a time;
- one active generated claim per user's newest active plan;
- one row per request;
- no automatic retry storm;
- indexed lookup by user, generation status, and sequence.

Different users may still invoke the function concurrently. For a rollout
around 200 users, keep this one-row contract, monitor provider 429/5xx rates,
Edge Function duration, and queue age, and add a server-side queue/rate
limiter before increasing concurrency. Do not change `maxLessons` to six as a
shortcut: that would multiply provider bursts and make failures harder to
recover. A queue worker can safely increase throughput later while retaining
the same row claim and validation rules.

## Local verification (no network, no provider spend)

Run from `flutter_app/`:

```bash
flutter test test/live_prompts_test.dart \
  test/grammar_v2_test.dart \
  test/adaptive_course_store_test.dart
```

This focused gate is the recorded 43-test green check. It covers:

- the fixed six-skill Unit 2 order and immediate authored readiness;
- the Grammar Guided/Complete schema and five-step contract;
- serial Debug-harness growth, one-row advancement, and bounded failure
  requeue;
- the Grammar Live prompt, including the no-answer-leak rule;
- CEFR checks, duplicate/invalid artifacts, and hydration preservation.

The broader course/audio contract can be run with:

```bash
flutter test test/unit_two_authored_content_test.dart \
  test/speak_roadmap_service_test.dart \
  test/course_artifact_codec_test.dart \
  test/course_practice_route_test.dart \
  test/course_vocabulary_ready_content_test.dart \
  test/lesson_audio_deck_service_test.dart \
  test/gemini_live_audio_service_test.dart \
  test/task_result_adapters_test.dart \
  test/narration_alignment_test.dart
```

These tests use in-memory SQLite, fixtures, and fakes; they do not call
Supabase or a model. The current worktree's separate `writing_course_v2_test`
widget sweep has two existing UI assertions that are not on this generation
gate; keep those failures separate from the green generation result.

The lane-to-test map is:

| Lane | Primary local coverage |
| --- | --- |
| Vocabulary | `course_vocabulary_ready_content_test.dart`, `adaptive_course_store_test.dart` |
| Reading | `unit_two_authored_content_test.dart`, `course_artifact_codec_test.dart` |
| Listening | `lesson_audio_deck_service_test.dart`, `gemini_live_audio_service_test.dart` |
| Writing | `course_artifact_codec_test.dart`, `writing_course_v2_test.dart` |
| Speaking | `course_practice_route_test.dart`, `speaking_task_plan_test.dart`, `speaking_translation_alignment_test.dart` |
| Grammar | `grammar_v2_test.dart`, `course_artifact_codec_test.dart`, `live_prompts_test.dart` |

The shared Store/Roadmap tests are intentionally run for every lane because
they prove the important cross-lane invariant: completion advances exactly
one ordered row and the next row cannot be opened until its artifact is ready.

Finish every code change with:

```bash
dart analyze lib/screens/speak/speak_course_activity_screen.dart \
  lib/screens/speak/speak_roadmap_screen.dart
git diff --check
```

## Real Debug/device verification

Debug is a device/integration check, not a substitute for local tests. It
uses the real authenticated Supabase project, the deployed Edge Function, and
the provider behind `ai-text`.

```bash
cd flutter_app
flutter devices
flutter run -d <DEVICE_ID> --device-timeout 30 \
  --dart-define=PARLESPRINT_COURSE_HARNESS_SKILL=grammar \
  --dart-define=PARLESPRINT_COURSE_HARNESS_ENABLED=true
```

`kDebugMode` is a hard second guard. The compile-time lane supports
`speaking`, `vocabulary`, `reading`, `listening`, `writing`, and `grammar`;
the current default is Grammar. Old generated rows remain in the database but
non-target personalized rows are hidden from this verification lane.

Verify in order:

1. Unit 2 shows all six authored cards immediately.
2. Complete the authored Grammar card (sequence 11).
3. Exactly one sequence-12 Grammar placeholder appears, then becomes ready.
4. Open it and confirm the correct CEFR level, five steps, no answer leakage,
   Live feedback, and completion state.
5. Repeat steps 4–5 three to five times. Each completion appends exactly one
   next Grammar row; no Vocabulary/Reading/etc. row is generated by the
   Grammar lane.
6. Reload between repetitions. The same ready artifact must hydrate locally
   and must not create a duplicate request.
7. If a request fails, inspect the row's durable error. The harness performs
   at most one explicit requeue; a second failure stays terminal until a fresh
   user action.

The last device pass left the Grammar Debug session resident on the physical
iPhone, and the remote Edge Function was hot-verified at version 42. Cost and
latency evidence is emitted as local NDJSON `AI_COST` events, including the
request, Edge response, preparation completion, and harness advance trigger.

### Latest Grammar Debug smoke pass

On 2026-09-08 the terminal-attached Debug build was hot-restarted with the
Grammar harness. The app reached the authenticated course screen, emitted one
Grammar preparation request, received the Edge response, and finished the
preparation without a client timeout. The same run opened the Grammar Live
socket, completed setup, and kept the socket resident for the lesson. A remote
ready artifact inspected during the pass was an A1 Guided/Present session with
five connected steps, three choices per guided blank, and English choice
meanings. The Live context used the current-step snapshot and answer-safe
guardrails; it does not send the hidden answer before checking.

The guided blank card now renders its English sentence meaning immediately
under the blank when Translate is selected. Checking a correct answer sends
only “Correct” plus the completed French sentence; an incorrect answer sends
only “Try again” plus one short clue. Advancing calls
`suppressCurrentReply`, replaces the Live context with the new current-step
snapshot, and sends one short screen-change instruction. This prevents a
previous step's verbose reply from delaying or bleeding into the next card.
Focused `grammar_v2_test.dart` coverage is green after the change. Manually
complete three to five cards on the attached device to verify the real
provider's spoken timing and the one-row-at-a-time future generation path.

Complete-mode workshop screens use the same generated session data (they are
not a separate hard-coded lesson). Its Live context now includes the exact
visible example, English instruction, tense, choices/glosses, and remaining
word bank. Concept stages advance one at a time; result speech follows the same
short Correct/complete-sentence or Try-again/clue contract as Guided mode.

## Release wiring

Release must use the same Supabase project and migrations, but never the Debug
harness:

```bash
cd flutter_app
./run_app.sh release --device <DEVICE_ID>
# or, for a distributable archive:
./run_app.sh ipa
```

`run_release_with_keys.sh` is a backward-compatible alias. These scripts pass
the compiled public Supabase configuration from
`secrets.local.properties`; do not run a bare Flutter command that omits the
Supabase URL/anonymous key. The client contains no service-role or provider
secret. Gemini Live credentials are minted by the authenticated Supabase
token function when a Live interaction is explicitly requested.

Before shipping a Release build:

1. Apply/verify the Supabase migrations, especially the generation columns,
   status constraint, regression guard, and generation index.
2. Deploy `prepare-course-lesson` from the checked-in source with JWT
   verification enabled. Never deploy it with JWT verification disabled.
3. Verify the remote function version contains `grammar` and
   `AUTHORED_SEQUENCE_CEILING = 11` (currently version 42).
4. Run one authenticated smoke test for each skill and complete one row to
   prove `completed → queued → generating → ready` end to end.
5. Build Release/Profile without harness defines. Even if a harness define is
   accidentally present, `kDebugMode` makes it inert outside Debug.
6. Confirm that completing a lesson automatically prepares only the next
   ordered row, and that a ready row is opened from local/cloud state without
   another provider call.
7. Monitor function duration, 429/5xx responses, failed-row count, queue age,
   and per-user generation attempts after rollout.

This keeps local, Debug, and Release on one data contract: only the trigger
differs. The artifact schema, row claim, validation, hydration, completion
and retry boundaries remain identical.

## Grammar implementation map

Course Grammar is one lane in the same Course pipeline; it is not a second
lesson generator. The request and response path is:

```text
Grammar card completion
  → SpeakRoadmap records the exact grammar content key as completed
  → AdaptiveCourseStore appends the next ordered grammar row (sequence +6)
  → SyncService mirrors the queued row to adaptive_course_sessions
  → prepare-course-lesson (authenticated Edge Function) claims one grammar row
  → ai-text generates the artifact with the current CEFR and unit context
  → validateGrammar rejects anything that is not Guided fill-in-the-blank
  → artifact_json + artifact_kind are saved as ready
  → SyncService hydrates the ready row
  → Grammar V2 opens the lesson and Gemini Live receives the current-step view
```

The authoritative Grammar contract is deliberately small and stable for all
levels:

- A1/A2 use high-frequency forms and one clear tense contrast.
- B1/B2 increase the contrast, clause complexity, and register, but keep the
  same interaction so progress never changes the learner's control surface.
- Every lesson has five connected steps.
- Every step has exactly one `___`, exactly three unique visible French
  choices, and one answer that appears in those choices.
- The English meaning is teaching context only; it must never reveal the
  missing French form before the learner checks.
- Complete word-bank and Roleplay modes remain Practice-only and are rejected
  if they arrive in a Course Grammar row.

The Edge Function owns authentication, newest-active-plan selection, the
sequence-12 boundary, one-row claiming, provider calls, validation, durable
errors, and the `queued → generating → ready/failed` transition. Flutter owns
the ordered unit, local hydration, completion, and Gemini Live screen guidance.
No service-role key or provider key is shipped in the app.

## Full-course production plan: Vocabulary → Grammar

Every generated unit after the authored foundation uses this fixed order:

| Unit position | Course lane | What it contributes |
| ---: | --- | --- |
| 1 | Vocabulary | Introduces the unit's useful words and target phrases. |
| 2 | Reading | Reuses about half of the active targets in a new, unit-specific scene. |
| 3 | Listening | Reuses the same unit targets in a separate audio situation. |
| 4 | Writing | Turns the targets into a short, level-matched production task. |
| 5 | Speaking | Moves the targets into guided Live conversation and feedback. |
| 6 | Grammar | Recycles the same targets through the CEFR-appropriate blank-choice pattern. |

The next unit receives retrieval evidence from the completed unit, not a fixed
story setting. Roughly half of the useful words/patterns may return, while the
unit context, people, place, and communicative goal are regenerated. This is
why a train can be followed by a bus, office, appointment, concert, or daily
conversation without losing continuity.

In Release, the learner completes one row at a time. The next row is created
and prepared automatically after the preceding row is completed. A ready
artifact is reused on reload and never regenerated. The roadmap has a
status-only buffer lane; there is no manual generation control. In the Debug
harness, the selected skill is filtered and the Unit 2 gate automatically
prepares the next same-skill row so the lane can be exercised three to five
times quickly. The other five lanes remain visible but are not generated by
that focused harness run.

### Production rollout gates

1. Apply the database migrations and verify the generation index, status check,
   and regression guard in the target Supabase project.
2. Deploy `prepare-course-lesson` from the checked-in source with JWT
   verification enabled. Confirm the deployed function includes
   `AUTHORED_SEQUENCE_CEILING = 11`, `grammar` in its skill whitelist, and the
   Guided Grammar validator.
3. Run the local contract suite, then one authenticated device smoke for each
   lane. For each lane prove `completed → queued → generating → ready` and
   reopen the app to prove hydration does not create a second artifact.
4. Build Profile/Release without harness defines. The second `kDebugMode`
   guard makes the harness inert even if a define is accidentally carried into
   the build command.
5. Roll out gradually and monitor Edge duration, provider 429/5xx responses,
   queue age, failed rows, generation attempts, and ready-artifact reuse.
6. Promote to TestFlight/production only after the six-lane journey has been
   completed from Vocabulary through Grammar on a clean account and on an
   existing account with prior ready rows.

### Persistence migration and reinstall recovery

The production persistence contract is in
`supabase/migrations/20260909022328_persist_course_practice_content.sql`, with
`supabase/migrations/20260909024009_restore_story_favorites.sql` repairing the
bookmark relation in environments whose old migration ledger said it existed
but the table was missing. Both are idempotent and have been applied to the
linked Supabase project. Together they cover the
ordered Course plan/session rows, generated Vocabulary/Reading/Listening/
Writing/Grammar artifacts, Speaking/Writing/Grammar Practice payloads, review
plans and attempts, vocabulary audio metadata, and private story/listening/
vocabulary media buckets, plus Story favorites. Every learner-owned row is protected by RLS and is
keyed by the authenticated user; ready artifacts are stored as JSON so a second
device can hydrate the exact lesson instead of asking the model to regenerate
it.

The migration history is reconciled and the linked database is currently up to
date. For a fresh environment, run:

```bash
cd flutter_app
npx --yes supabase@2.116.0 db push --linked --yes
npx --yes supabase@2.116.0 db push --linked --dry-run --yes
```

The second command must report `Remote database is up to date.`. After a
delete/reinstall or a second-device sign-in, the expected path is local cache
miss → authenticated Supabase hydration → the same ordered rows and ready
artifacts reappear. A provider call is allowed only for a queued row; a ready
row must be reused. To prove this manually, finish one row, wait for its next
row to become ready, terminate/reinstall, sign in as the same user, and verify
that the completed row, generated artifact, score, and next-row state are all
still present.

The focused Debug build is for fast lane testing; it does not replace this
recovery test. Release/Profile builds use the same tables, policies, Edge
Function, and artifact validators, with only the Debug harness disabled.

The client restore pass is also idempotent for legacy local databases: notes
and transcripts use explicit UUID lookups when an old install lacks its
partial index, credit-usage restore rows are recomputed by stable id, and
starter stories are inserted with a duplicate-safe guard. These local guards
keep unrelated cache noise from hiding a real Course sync failure.

### Interpreting the Debug diagnostic

The client logs one safe summary after every preparation call:

```text
Course preparation response: processed=true|false remaining=<n> ...
```

`processed=true` means a row was claimed and prepared. `processed=false,
remaining=0` means there is no eligible queued Grammar row for the current
authenticated active plan; it is not evidence that the Grammar JSON failed
validation. Complete the selected gate; the completion callback creates the
next queued row automatically. If the app was interrupted, reopen Course to
resume the same queued row. A provider/schema failure is represented instead
by a durable `failed` row and its bounded `generation_error`; the harness
retries that row once and then stops rather than looping forever.
