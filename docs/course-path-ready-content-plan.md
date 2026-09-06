# Course Path Ready-Content Plan

## Product contract

- Course lessons never generate learner content after a lesson card is tapped.
- Course lessons open only content that has already been generated, validated, persisted, and hydrated to the device.
- Foundation lessons 1–4 keep their current curriculum and behavior unchanged; lesson 5 is the authored A1 guided “Introduce yourself” bridge.
- The first personalized batch contains exactly five lessons (lessons 6–10).
- A new batch contains exactly five lessons and is generated before the learner exhausts the current ready batch.
- Completed and active lessons are immutable. Updated settings and learning evidence affect only a newly created future batch.
- Course lessons reuse the existing Reading, Listening, Writing, Grammar, Vocabulary, and Speaking practice renderers. Course screens do not own generation.
- Supabase owns durable generation and retry state so app suspension, termination, reinstall, or account switching cannot lose a batch.
- Shared catalogs remain shared. Account deletion removes all learner-owned database rows, generation work, and Storage objects.

## Confirmed implementation defaults

- Personalized batch size: 5.
- Foundation size: 5 (four sound foundations plus one prebuilt A1 guided speaking lesson).
- Generation trigger: begin preparing the next batch when one unopened ready personalized lesson remains. This prevents a zero-ready gap while retaining the requested five-lesson buffer.
- Personalization uses an 80/20 compact snapshot: onboarding/profile settings plus recent evidence, weak areas, neglected skills, and a small number of transcript/target-language signals.
- Each batch freezes its learner snapshot. Routine evidence updates do not rewrite an in-progress batch.
- Vocabulary course lessons contain exactly five words, five prepared examples, and one connected five-sentence mini-story. The learner can choose Words only or Words + context without invoking content generation.

## Current defects being replaced

- Adaptive Course currently creates blocks of 20 lightweight specifications.
- Sessions 6–20 use a mostly fixed primary-skill route, so focus selections mainly affect context instead of controlling the lesson mix.
- The adaptive fingerprint includes changing learning evidence and can replace future routes too frequently.
- Home and Course use different launch routes.
- Reading, Listening, Writing, and Grammar receive `autoStart: true` from Course and generate after navigation.
- Course Vocabulary generates a random 3–5 word deck on screen open.
- Vocabulary contextual examples can be generated from inside the flashcard screen.
- Generated content records have no authoritative link to their Adaptive Course session.

## Target data ownership

### Adaptive course session

Each session remains the source of truth for:

- stable session ID and content key
- sequence and batch
- primary and supporting skills
- learner-facing title and context
- competency, target phrases, grammar focus, and success criteria
- frozen learner snapshot/version used for generation
- generated artifact kind and ID
- generation state: queued, generating, ready, or failed
- attempt count, generation version, timestamps, and safe error summary

### Generated artifacts

The Adaptive Course session owns its complete validated artifact. Existing generated-content tables remain the source for independent Practice/Lab libraries; Course does not duplicate or regenerate their content. A unique session ID and conditional claim prevent duplicate Course generation.

### Queue

The learner-owned Adaptive Course rows are the durable queue: `queued → generating → ready/failed`. The authenticated mobile client can request preparation only for its own account. The server function verifies the JWT, reloads the persisted session brief, conditionally claims one row, validates the full artifact, and commits it atomically. Interrupted `generating` rows are recovered after a bounded stale interval.

The mobile sequence is strict: persist the plan, persist each session specification in course order, confirm success, then invoke the worker. Each worker request claims one row, and the app hydrates that completed row before requesting the next. A failed plan/session push is retained in the local sync outbox and retried on foreground resume; generation never starts against a local-only queue.

## Personalization policy

For each new five-lesson batch:

1. Read current goal, CEFR level, session duration, interests, and selected focus skills.
2. Summarize recent completed course and practice sessions.
3. Select a small number of weak vocabulary, grammar, pronunciation, and transcript signals.
4. Track recently used and neglected primary skills.
5. Score candidate lesson skills using selected priorities, observed need, and coverage balance.
6. Produce a deterministic five-session mix with one primary skill per session and up to three supporting skills.
7. Freeze the snapshot and generated specifications for the batch.
8. Do not regenerate completed or active sessions after settings/evidence changes.

## Vocabulary-first implementation

1. Add a persisted course-session link for generated vocabulary sets.
2. Make course vocabulary deck size exactly five; remove random deck sizing.
3. Persist the five words and all contextual material before marking the lesson ready.
4. Store one prepared example per word and one connected five-sentence mini-story.
5. Keep vocabulary text/content complete before readiness; audio playback remains presentation behavior and never creates or changes the five-word lesson payload.
6. Open Course Vocabulary by artifact ID only.
7. Keep Words only and Words + context as presentation choices over the same saved artifact.
8. Retain independent vocabulary-set creation in the Vocabulary Lab; it must not be used by the Course launcher.
9. Add tests proving no lesson-agent generation method runs after a ready course vocabulary lesson is tapped.

## Full course implementation

1. Change adaptive planning from blocks of 20 to a five-foundation plus five-personalized initial route.
2. Preserve foundation specifications and deck routing exactly.
3. Generate subsequent batches of five only at the refill boundary.
4. Separate stable profile identity from batch learning evidence so evidence cannot continuously replace a plan.
5. Add the session-to-artifact contract locally and in Supabase.
6. Use durable session generation state and an idempotent authenticated worker.
7. Port the validated content-generation contracts needed by Course to the server worker.
8. Generate, validate, persist, and link one lesson at a time.
9. Hydrate artifact links and generated payloads before exposing lesson cards as ready.
10. Replace both existing Course launch paths with one ready-content launcher.
11. Remove `autoStart` generation from Course navigation while retaining explicit generation in independent Practice/Lab surfaces.
12. Trigger the next five-lesson batch when one unopened ready lesson remains.
13. Cancel queued work and reject late worker commits when account deletion begins.

## Readiness and UI rules

- Foundation cards: available under existing progression rules.
- Personalized ready card: tappable and opens its persisted artifact immediately.
- Queued/generating card: visible as Preparing and not tappable.
- Failed card: not tappable; retry happens outside the lesson screen.
- No Course loading shell, AI-generation dialog, or generation retry button appears after a card tap.
- Local payload absence after reinstall is a hydration state, not permission to generate. The app hydrates the linked artifact before enabling the card.

## Account deletion repair

1. Reconcile the deployed and repository `delete-account` Edge Function.
2. Remove all user-prefixed objects from story-covers, vocabulary-audio, and listening-audio.
3. Cancel/delete course-generation jobs and learner-owned artifacts.
4. Explicitly clean tables that do not use `ON DELETE CASCADE` or correct their ownership constraints safely.
5. Revoke sessions before deleting the Auth user.
6. Preserve shared catalogs and validated system content.
7. Delete the Auth user only after dependent Storage and database cleanup succeeds.
8. Clear local credentials/data only after confirmed remote deletion.
9. Verify zero remaining learner-owned rows and Storage objects.

## Authorized production test-account deletion

Permanently delete all learner-owned data, Storage objects, sessions, and Auth identities for:

- `thoufeekbaber@gmail.com`
- `thoufeekbaber1@gmail.com`
- `thoufeek.orbmedic@gmail.com`

Shared catalogs must not be deleted. Deletion happens after the deletion path is repaired and verified.

## Implementation status — September 5, 2026

- Completed: foundation lessons 1–4 remain fixed and lesson 5 is wired to the authored `speaking_a1_01_introduce` lesson.
- Completed: initial route is five foundations plus five personalized specifications.
- Completed: subsequent refills append five when one unfinished lesson remains.
- Completed: current batches are stable; new evidence is consumed by the next batch.
- Completed: Vocabulary requires exactly five words and five persisted bilingual story sentences.
- Completed: Course uses one launcher and no longer contains the legacy live-generation course screen.
- Completed: Reading, Listening, Writing, Grammar, and Vocabulary decode persisted artifacts; a Course tap never calls the lesson generator.
- Completed: Listening readiness includes a stored audio object; missing audio fails preparation instead of synthesizing after the tap.
- Completed: Supabase schema migrations and authenticated `prepare-course-lesson` function are deployed.
- Completed: `delete-account` v11 revokes all refresh-token sessions, removes learner storage and all known non-cascading learner tables, then deletes Auth.
- Completed: shared Speaking/Writing catalog creator references now use `ON DELETE SET NULL` and survive account deletion.
- Completed: session 5 upgrades old generated vocabulary rows in place, clears their obsolete artifact, and opens the canonical Speaking lesson.
- Completed: course preparation is capped at five rows per pass, claims one row per Edge Function request, shares one in-flight client worker across foreground callers, and records structured start/success/failure logs.
- Completed: course plan/session pushes are confirmed before preparation, failed pushes persist in the supported sync outbox, and each generated lesson hydrates immediately before the next worker request.
- Completed: `tool/delete_test_user.dart` provides a dry-run-first, exact-email-confirmed, allowlisted test-account cleanup path that preserves shared catalogs and verifies Auth/database/Storage removal.
- Completed: all three authorized production test accounts were permanently deleted.
- Completed: the in-app delete action calls the authenticated v11 function, revokes all sessions, and clears the local database/preferences only after remote success.
- Verified: each authorized UUID has zero Auth, profile, adaptive-course, generated-content, session, note, chat, vocabulary-audio-cache, and Storage rows.
- Verified: all 127 shared Speaking catalog rows survived; their deleted creator references were anonymized.
- Verified: deletion/local-reset regression tests pass 2/2; unauthenticated delete requests return 401.
- Verified: focused vocabulary/course/auth/Home tests pass; Flutter analyzer reports no errors; `git diff --check` is clean.

## Verification gates

- Foundation lessons 1–4 are unchanged; lesson 5 is immediately ready and uses the canonical prebuilt A1 guided Speaking lesson.
- Initial route has five foundation lessons and exactly five personalized lessons.
- Every personalized card marked ready has one valid persisted artifact.
- Course Reading, Listening, Writing, Grammar, Vocabulary, and prepared Speaking navigation performs zero AI generation calls.
- Vocabulary contains exactly five words and complete pre-generated context.
- Killing the app during generation does not lose or duplicate jobs.
- Reinstall/sign-in restores the same course and linked artifacts.
- New learning evidence affects only the next batch.
- One remaining ready lesson triggers a single next-batch request.
- Account switching never exposes another learner’s jobs or artifacts.
- Delete Account leaves zero learner-owned database rows and Storage objects and removes the Auth identity.
- Supabase RLS/security and performance advisors are reviewed after schema changes.
- Flutter analyzer, focused regression tests, sync/auth tests, and `git diff --check` pass before release handoff.
