# Course generation optimization plan

## Gemini cost-control addendum (2026-09-07)

This plan was checked against the official Gemini Live best-practices,
session-management, pricing, optimization, speech-generation, and Live API
reference pages, plus Google's Live API cookbook:

- https://ai.google.dev/gemini-api/docs/live-api/best-practices
- https://ai.google.dev/gemini-api/docs/live-api/session-management
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/optimization
- https://ai.google.dev/gemini-api/docs/speech-generation
- https://ai.google.dev/api/live
- https://github.com/google-gemini/cookbook/blob/main/quickstarts/Get_started_LiveAPI.py

The important billing fact is that Live input includes accumulated session
context. Audio is tokenized, and requesting input/output transcriptions adds
text tokens. A long, repeatedly resumed conversation therefore costs more on
each later turn even when the visible prompt is small. The cookbook's
`contextWindowCompression` configuration is the safe mitigation; it does not
change the tutor's voice or turn-taking behavior.

Model choice is deliberately conservative:

- Keep `gemini-3.1-flash-live-preview` for an active voice-to-voice tutor. It
  is the current Live model already working in the app; `gemini-3.1-flash-lite`
  is text-only and cannot replace it. `gemini-3-flash-preview` is not a Live
  endpoint. The 2.5 native-audio preview has the same listed audio rates and
  did not meet the app's reliability bar in the existing test.
- The current catalog also lists `gemini-3.5-flash-lite`, but its standard
  input/output rates are higher than 3.1 Flash-Lite. It is therefore not a
  cost optimization for this workload. Batch/Flex are cheaper for offline
  work, but they are not suitable for the learner's synchronous request.
- Keep Course text on the existing one-request OpenRouter Practice-compatible
  path. Do not spend Live audio tokens authoring text.
- Keep cached PCM playback local-first. A cache hit must never open a Live
  socket. TTS is not substituted blindly: the official TTS rates and output
  semantics do not guarantee a lower cost for these short clips, and it would
  change the currently accepted audio quality.

### Implementation now

1. Add cookbook-compatible Live context-window compression (8,000 trigger,
   4,000 sliding target) and record the configuration in debug telemetry. The
   target is the retained conversational-turn window; the static tutor rules
   and current lesson contract remain separate and are preserved.
2. Bound only dynamic learner-profile and lesson-context text; preserve the
   tutor's core prompt and current voice/response behavior.
3. Make non-auto-start Grammar preparation explicit. Opening the Grammar
   library must not generate all three modes in the background. Protect async
   work from disposed widgets and use one generation attempt; the learner can
   explicitly retry after a visible failure.
4. Cancel Course audio continuation when the roadmap is disposed or the app is
   suspended, so a completed text lesson cannot keep opening missing-audio
   calls after the user leaves.
5. Add a root lifecycle guard that closes any remaining Live owner on app
   pause/hidden/termination, even if a route-level observer misses the event.
6. Correct local cost telemetry: cache hits are zero-provider events, while a
   failed provider attempt is marked billing-unknown rather than falsely
   reported as `$0`.
7. Send only a compact learner calibration summary (level, goal, up to two
   focus areas, session length, and one recent issue), capped at 500
   characters. The lesson contract remains separately bounded because the
   app-directed stages depend on its exact choreography.

### Non-negotiable invariants

- No provider call on Course/Grammar entry, tab changes, replay, or cache hit.
- At most one explicit Course text request per Generate action.
- At most one reconnect for a genuine Live network loss; no background retry
  loop.
- A ready lesson is never replaced by a later failed generation.
- Local SQLite and Supabase Storage remain mirrors; storage changes are not
  replaced by this optimization.

### Verification gates

- `flutter analyze` for all touched Dart files.
- Focused Course/audio/Grammar tests and `git diff --check`.
- Source-level assertions that entry paths do not call a provider.
- No device launch, Live socket, Edge Function invocation, or billing test is
  used for verification.

### Verification record (2026-09-07)

- Touched-file `flutter analyze`: clean.
- Full `flutter analyze`: no errors; remaining diagnostics are pre-existing
  style/deprecation warnings outside this change.
- Focused Course/Unit 2/audio tests: all passed.
- Grammar V2 tests: all passed.
- Full Flutter suite: 8 pre-existing failures remain in migration/theme/funnel
  contract tests; none are on the Live, Course, PCM, or cache paths changed
  here.

## Goal

Make Course use the same cost profile as Practice while keeping the Course
roadmap, authored Unit 2 lessons, local SQLite cache, Supabase mirror, and
one-time PCM deck behavior intact.

The invariant is simple: an explicit Generate action creates at most one new
lesson. A ready lesson is immutable and is never regenerated, replaced, or
hidden by a later failure. Reopening a lesson reads the local/cloud artifact
and existing audio cache; it does not call a model.

## Provider decision

Course text should use the existing Practice text route (OpenRouter's pinned
JSON-capable model) rather than a Course-only direct Gemini route. This is not
a new AI pipeline: it is the existing `LessonAgentService`/`ai-text` contract
with a short Course prompt. It avoids charging Gemini for ordinary lesson
authoring and keeps the provider behavior identical to Practice.

Gemini remains only where it is actually needed:

- Gemini Live for an explicitly active tutor interaction.
- Gemini Live audio for a missing, one-time PCM clip during explicit lesson
  generation.
- No Live socket for Course entry, navigation, background warming, or replay.

The current official model list has `gemini-3.1-flash-lite` for inexpensive
short text and `gemini-3.1-flash-live-preview` for Live audio. There is no
official Gemini 3.0 Flash Live endpoint in the model list; `gemini-3-flash-preview`
is text-only. Do not invent or silently substitute a model identifier.

## Implementation steps

1. Keep generation user-triggered and bounded to one server claim/request.
2. Remove Course-specific provider selection so Course text follows Practice's
   provider contract.
3. Keep Course context compact: level, onboarding goal/interests, and a small
   recent-session summary. Never send a full transcript or the whole history.
4. Disable provider retries for Course. A failed request becomes a visible
   failed row; only a later, explicit Generate tap may request a fresh lesson.
5. Keep the local-first audio deck. Authored Unit 2 Listening imports the
   existing `course-shared/unit-two-listening.wav` once from Supabase Storage,
   slices it locally into sentence clips, and never opens Gemini. Personalized
   lessons check local PCM, then the Supabase mirror, and only then generate one
   missing clip during an explicit preparation action. Serialize missing clips
   so a lesson cannot open several Live sockets at once.
6. Preserve ready artifacts during remote hydration. A queued/failed snapshot
   with a null artifact must not overwrite a ready local artifact.
7. Keep authored/default Unit 2 content out of personalized generation. If its
   artifact is already present, opening it must not author new text.
8. Keep one Live socket per active lesson and close it on route exit, app
   suspension, completion, or idle timeout. Defaults remain opt-in.
9. Verify with static tests, SQLite persistence tests, artifact/deck tests,
   and source-level checks that no Course entry path calls a provider.
10. Keep audio preparation behind the explicit Play action for Reading and
    Listening. Course entry only decodes the saved artifact; it never builds a
    missing deck just because the learner opened the lesson.

## Acceptance criteria

- Opening Course, switching tabs, and reopening a ready lesson produce zero
  model requests. Replaying a cached lesson is also zero-cost; only an
  explicit Play on a missing personalized deck may prepare it. Unit 2
  Listening's shared deck remains zero-provider-call even on first Play.
- One Generate tap produces no more than one Course text provider request.
- A provider failure produces no automatic retry and does not alter any ready
  lesson.
- A successful lesson remains present after a later lesson failure and after a
  local/remote hydration cycle.
- Unit 2/default lessons remain available and are never routed through the
  personalized generator.
- Unit 2 Listening reuses its single shared WAV and stores locally sliced
  clips; no Gemini call is made on open. Personalized PCM is generated only
  for missing segments, stored locally, mirrored to Supabase, and reused on
  every later open.
- Practice uses the same cache/deck path; a missing clip is prepared only from
  the learner's explicit Play action, never from screen entry or a background
  warmup.
- `flutter analyze`, the focused Course/audio tests, and `git diff --check`
  pass without launching the app or making a provider request.

## Verification record

- The local source for `ai-text` and `prepare-course-lesson` contains the
  cost-control changes. They have **not** been redeployed or invoked during
  this pass, so verification did not spend another provider request.
- Focused Course, Unit 2, roadmap, vocabulary, PCM-cache, and hydration tests
  pass.
- Targeted analyzer run for all touched Course/audio files reports no issues.
- The full repository suite still has unrelated pre-existing failures in
  competency/evidence/momentum and other legacy contract tests; those are not
  on the Course generation or storage path and were not changed here.
