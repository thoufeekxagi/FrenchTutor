# Review and Warm-up Framework

Status: implemented in the Flutter app as a local-first, resumable framework.

## Product decision

Review and Warm-up share one planner and one generation pipeline, but they look in opposite directions:

- **Review** looks backward across completed Course and Practice activity. It prioritizes language that is due, repeatedly missed, weakly retained, or important but under-practised.
- **Warm-up** uses a bounded rolling Course window: up to three recent completed
  Course lessons provide the bridge, and up to three active/planned generated
  lessons provide the forward preview. It previews the next situations,
  grammar, vocabulary, generated activity content, and success criteria in a
  short low-pressure activity without treating future material as mastered.

The learner can choose Speaking, Reading, Listening, or Writing. Smart mode chooses the best format from the evidence. The selected format changes the activity, not the evidence contract.

## Durable data contract

Existing tables remain the source of truth and are not replaced:

- `sessions` and `messages` store completed Course and Practice sessions and learner turns.
- `ai_sessions.transcript_json` stores Live Tutor transcripts.
- `writing_submissions` stores writing and feedback.
- `vocab_reviews`, `vocab_cards`, and `vocabulary_sessions` store recall and SRS evidence.
- `lesson_progress`, `daily_sessions`, `learner_competency_states`, mistake tags, and exam attempts store structured outcomes.
- `adaptive_course_sessions` stores the rolling Course queue and each lesson's
  generation artifact. Warm-up reads the current/upcoming window from this
  table and Review reads completed evidence from the same durable rows.
- Generated reading/listening/writing/grammar artifacts remain reopenable in their existing stores.

The new review ledger adds only the missing provenance and resumability:

1. `review_plans` freezes the exact bounded snapshot and plan brief used for generation.
2. `review_plan_targets` stores ranked targets and why each target was selected.
3. `review_attempts` records generation/start/completion state and links the attempt to the generated activity or session.

This means a review can be resumed, audited, or regenerated from the same evidence without silently changing because the learner completed another lesson later.

On sign-in or a fresh install, the sync layer hydrates `review_plans`,
`review_plan_targets`, and `review_attempts` after the normal Course/session
rows. The frozen brief includes the forward lesson IDs and bounded context, so
an already-generated Review or Warm-up can be reopened and retried without
losing its lesson window.

## Planner flow

```text
Course/Practice completion
        |
        v
Persist normal session/transcript/results
        |
        v
UniversalLearningDataService.buildSnapshot()
        |
        +--> Review: rank past targets and weak signals
        |
        +--> Warm-up: read up to 3 completed + 3 active/planned Course sessions
             and rank future targets from their full bounded lesson content
        |
        v
Freeze review_plans + review_plan_targets
        |
        v
Send bounded context + target IDs to GPT lesson generation
        |
        v
Save generated artifact + review_attempts result
        |
        v
Open the normal Reading / Listening / Writing / Speaking activity
```

## Context sent to GPT

The prompt is bounded and labelled. It includes:

- CEFR level, goal, and interests.
- Plan kind and selected activity mode.
- A universal evidence fingerprint and internal source IDs.
- Recent topics and compact transcript excerpts.
- Vocabulary/SRS signals, writing feedback, performance, competency, and repeated mistakes.
- Ranked targets with a reason and priority.
- A 60% retrieval / 40% controlled-novelty rule.

Source IDs are provenance only and must never be shown to the learner. The model must not invent a learner error when the evidence does not support it, copy a prior transcript, or turn every weak signal into a correction.

## Generation contract

Every generated activity must:

1. Have one clear objective.
2. Use at least one ranked retrieval target.
3. Add at most one small next-step challenge.
4. Stay within the requested CEFR level and duration.
5. Return learner-facing content through the existing validated lesson/artifact schema.
6. Preserve the plan ID and target IDs in the local attempt metadata.

## Completion guarantees

The app saves the normal Course/Practice data before the review planner reads it. A review plan is saved before GPT generation starts. A review attempt is saved before the activity opens. Generated reading/listening artifacts are saved before navigation. If generation fails, the plan and failed attempt remain available for retry; no learner history is deleted.

Each completed Course skill also writes one learner-owned session row tagged with
its skill and `content_key`. Speaking, Reading, and Listening attach a bounded
transcript; Vocabulary, Grammar, and Writing attach a bounded generated-lesson
snapshot (with an in-memory artifact fallback if the artifact write is still
in flight). The session and message ledgers sync to Supabase and are restored
on the next device before Review/Warm-up builds its context. The forward schema
and RLS contract live in
`flutter_app/supabase/migrations/20260909093000_course_session_ledger_rls.sql`;
this is additive and intentionally does not backfill stale developer rows.

## Warm-up rules

Warm-up is intentionally shorter than Review. It should preview:

- the last three completed Course situations as a short retrieval bridge;
- up to three active/planned Course situations, including their bounded
  generated lesson artifacts when available;
- two to four key words or phrases;
- one grammar pattern or pronunciation/context cue;
- one tiny production check;
- what success will look like in the next lesson.

Warm-up must not teach the entire future lesson or mark future material as mastered.

## Implementation checklist

- [x] Document the review/warm-up contract.
- [x] Add local durable plan, target, and attempt tables.
- [x] Add a store and Riverpod provider.
- [x] Rank evidence from the existing universal snapshot.
- [x] Add a rolling three-completed / three-upcoming Course preview context for Warm-up.
- [x] Persist generated review metadata and attempt state.
- [x] Hydrate review plans, targets, and attempts from Supabase on sign-in.
- [x] Expose Review and Warm-up in Practice.
- [x] Add Supabase SQL with ownership RLS for the new ledger tables.
- [ ] Run the SQL migration against the production Supabase project after reviewing the generated migration in the deployment pipeline.
# GPT-5.6 Review Composer Addendum

## Deterministic evidence boundary

Review is not allowed to treat every account-level learning row as recent
context. It first freezes the completed Course and Practice window, then only
admits transcript, message, SRS, vocabulary, and mistake evidence that can be
placed inside that window. Account-level SRS state is eligible only when its
review history is tied to one of those source sessions. Internal generated
entry IDs are never learner-facing Review text.

The local planner resolves the requested mode and primary theme once. GPT-5.6
Luna composes the lesson inside those constraints; it does not re-route Smart,
choose a new setting, or invent a café/restaurant/character scenario.

Smart Review is a unified, non-Live lesson. It combines vocabulary, grammar,
reading, listening, writing, and a short controlled speaking drill in one
validated blueprint. It never opens Gemini Live, roleplay, or Free Talk.

Explicit Speaking Review uses the same controlled speaking flow as Course and
Practice: fixed bilingual targets, hear → speak → check, with no open-ended
conversation. The optional tutor-helper Live session is disabled for Review.
Free Talk is a separate, unstructured feature available only from the main
Practice window.

A composer response that introduces an unsupported stock setting is rejected
before it reaches any Review activity. Historical session titles remain
available to the GPT dossier as provenance, but they are never used as the
Review's primary roleplay theme.

This provenance rule is the acceptance test for Review quality: if a target
cannot answer “which recent Course or Practice session produced this?”, it is
not eligible for the Review card or activity.

The Review feature now has a model-authored composition step before an
activity opens. Existing Course and Practice activity engines are reused; the
Review path chooses them explicitly and does not change the main Free Talk
flow.

When a completed session is written, the app queues a non-blocking refresh of
`review_context_cache`. This is only a replaceable speed index; the normal
learning tables remain authoritative. The index contains bounded Course and
Practice summaries, recent learner transcript excerpts, vocabulary, grammar,
writing, exam, mistake, and performance signals.

When Review starts:

1. The app freezes the current local review plan and persists it.
2. GPT-5.6 Luna receives one structured learner dossier containing the recent
   Course and Practice window, the learner profile, and evidence-backed weak
   signals.
3. GPT returns a JSON `ReviewBlueprint` with the best format, topic, targets,
   grammar, lesson arc, source session ids, and a concise teaching contract.
4. Smart Review renders the validated mixed blueprint and launches the
   existing Reading, Listening, Writing, and controlled Course speaking
   activities from it. Explicit Speaking Review launches only the controlled
   Course speaking flow. None of these paths receives the raw history again,
   and none starts Gemini Live.

For Writing specifically, Review and Warm-up call the same validated Course
Writing generator used by the Writing Course, persist the resulting
`WritingCourseLesson`, and open `WritingCourseLessonScreen`. They never open
the legacy Writing task screen. The generator receives only the bounded
Review/Warm-up contract plus the learner's current level, known vocabulary,
and mistake signals; the lesson screen owns the current inline tutor contract.

Smart Review prepares its four interactive artifacts once, before the first
stage opens. The learner then completes guided speaking, reading, listening,
and writing in that order. Each stage returns an explicit completion result;
the next stage opens automatically, and the active stage is locked while it
is running. Vocabulary and grammar remain visible as the shared lesson
contract rather than spawning duplicate child generators.
5. The blueprint and generated activity metadata are stored with the Review
   plan. The completed activity remains in the normal learning stores and will
   shape the next Review.

There is no silent provider fallback in this Review path. If the Review
composer cannot produce a valid blueprint, the Review attempt reports a
failure and the normal Course/Practice data remains safe and available.
