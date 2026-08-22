# Speaking + adaptive course: end-to-end verification contract

Status: implementation source of truth  
Scope: onboarding, Home, Course, Practice, universal speaking setup, live tutor, completion, and adaptive course progression.

This document is the checklist to follow before changing the speaking flow. It prevents the old Speaking Studio/legacy roleplay route from becoming a second source of truth.

## 1. Product contract

The learner has one cohesive course pathway:

```text
profile/onboarding
  -> adaptive course block (20 lightweight session specifications)
  -> Speaking Home
  -> Speaking hub (Course / Practice) when the learner selects See all or Roleplay
  -> course lesson detail or roleplay catalog/detail
  -> universal speaking setup (only for custom sessions)
  -> generated SpeakingTaskPlan
  -> SessionScreen live tutor
  -> durable completion + adaptive route update
  -> refresh Home/Course
  -> next 20-session block after the current block is complete
```

The rich lesson, transcript, audio, and artwork are generated when a session is opened. The adaptive course first stores the stable specification so the roadmap is immediate and resumable.

## 2. Entry-point contract

Every entry point must use the same live speaking implementation:

| Entry point | Expected route | Expected behavior |
| --- | --- | --- |
| Onboarding / first practice | `SpeakingPracticeScreen` | Three-minute or selected-duration setup, then live tutor. |
| Global Home dashboard | `SpeakingStudioScreen` | Restored dark, image-led Home with Next Up, quick starts, progress, path cards, and Explore. Its Speaking action opens the independent setup. |
| Practice tab → Speaking | `SpeakingPracticeScreen` | Opens the independent speaking setup. The parent Practice tab still contains listening, reading, writing, grammar, vocabulary, and exam work. |
| Speaking Home → See all / Roleplay | `SpeakingHubScreen` | Opens the Course / Practice sub-setup without replacing Speaking Home. |
| Speaking Course row | `SpeakCourseActivityScreen` → `SpeakingLessonDetailScreen` | Shows the lesson prompt, tutor lesson, speaking drill, and translation rows before Start lesson. |
| Speaking Practice → Roleplay | `SpeakingHubScreen` → `SpeakingRoleplayDetailScreen` | Shows Hot/New/Top today, scene cards, scenario, goal, and target phrases before Start roleplay. |
| Custom mode / onboarding | `SpeakingPracticeScreen` | Uses the selected guided, roleplay, free-talk, TEF/TCF, picture, or pronunciation mode. |

The old `Speaking Studio`/scene-brief renderer is not an active route. It may remain only as source-compatible dead code for old records; no current entry point should navigate to it.

## 3. Adaptive block contract

- A block contains exactly 20 ordered session specifications.
- Session sequences are one-based: 1–20 are block 0, 21–40 are block 1, and so on.
- `contentKey` is stable for the life of a session and is the identity used by local storage, sync, course progress, and generated practice.
- The next block is appended only after all unfinished sessions in the current block are completed and the plan is refreshed.
- A profile change creates a new plan version, preserves completed sessions, and regenerates only future sessions using the new level, goal, duration, and interests.
- Every block contains at least one primary `speaking` anchor and one primary `roleplay` transfer anchor, even when the learner heavily weights another skill.
- A1 sound foundations remain first. The speaking anchors begin after the foundation slots; A2/B1/B2 follow the same pathway with level-calibrated prompts.

### Block acceptance checks

- [ ] Fresh profile produces 20 sessions.
- [ ] Sequences are 1 through 20 with unique `contentKey` values.
- [ ] `blockIndex == 0` and `blockPosition` runs 1 through 20.
- [ ] The first block contains primary `speaking` and `roleplay` sessions.
- [ ] Completing only 15 sessions does not append a second block.
- [ ] Completing all 20 and refreshing the plan produces exactly 40 sessions.
- [ ] Sessions 21–40 have `blockIndex == 1` and positions 1 through 20.
- [ ] The second block also contains primary `speaking` and `roleplay` sessions.
- [ ] No duplicate sequence or `contentKey` is introduced.

## 4. Course session contract

When a roadmap item is opened:

1. Mark the adaptive session `active` using its `contentKey`.
2. Render the speaking lesson detail first; do not auto-launch a generic live call.
3. Pass the course unit, title, context, target phrases, level, duration, and `contentKey` into the speaking request when Start lesson is tapped.
4. Map the primary skill to the correct mode:
   - `speaking` → Guided conversation: hear, repeat, receive one correction, retry, transfer.
   - `roleplay` → Roleplay: stay in the scene and reach the practical goal.
   - `freeTalk` → Free talk: natural conversation with level-appropriate coaching.
5. Build the live `SpeakingTaskPlan` at the learner's CEFR level.
6. Store the live session under the same `contentKey`.
7. On return, record course activity and elapsed time.
8. When the course completion rule is met, write the durable completion row and mark the adaptive session completed.
9. On the next Home/Course refresh, `ensureCurrentPlan` exposes the next session or appends the next 20-session block when the current block is complete.

## 5. Speaking mode contract

The universal picker exposes:

- Guided conversation
- Roleplay
- Free talk
- TEF / TCF Section A
- TEF / TCF Section B
- Picture description
- Pronunciation repair

Each mode must preserve:

- level: A1, A2, B1, or B2;
- topic and course context;
- goal and duration;
- tutor persona;
- exact stage mapping;
- the same `SessionScreen` and result flow.

When a profile-driven entry point creates the universal setup with no pinned
course context, the setup starts from the learner's stored profile level rather
than the request constructor's safe A1 default. A course, onboarding trial, or
review request carries a pinned level and keeps that level exactly.

The first three speaking sessions may introduce the active tutor. Later sessions begin the activity directly. This count is based on stored speaking stages, including guided, roleplay, exam, and free-talk sessions.

## 6. CEFR behavior

The selected level is an explicit session contract. The live session receives
the selected setup level as `levelOverride`; the learner profile cannot silently
replace it. `SpeakingTaskPlan.liveContext` repeats the same lock next to the
lesson stages, so the UI choice and the tutor contract cannot drift apart.

| Level | Prompt behavior | Feedback behavior |
| --- | --- | --- |
| A1 | Tutor turns target 3–6 words; introduce at most one new content word; concrete present-tense situations; short English glosses; no idioms, abstraction, or multi-clause questions. | Model first, then one short learner turn; correct one high-value issue and immediately model/retry it. |
| A2 | Tutor turns target 5–9 words; introduce at most two new content words; everyday situations with simple past/future references; English only when blocked. | Correct clarity, tense, agreement, and useful vocabulary without turning the exchange into a lecture. |
| B1 | Tutor turns target 8–14 words; connected French, reasons, opinions, practical follow-ups, and no automatic translation. | Coach coherence, connectors, register, natural reformulation, and repair after the learner finishes. |
| B2 | Tutor turns target 10–18 words; mostly French, nuance, reformulation, and independent answers; idioms only when topic-appropriate. | Coach precision, range, register, discourse structure, and pronunciation patterns. |

Never let a topic or generated scene raise the French above the requested level.

## 7. Persistence and resume checks

- [ ] Closing a live session does not mark it complete accidentally.
- [ ] Completing the essential loop writes a durable `sessions` row with the course `contentKey`.
- [ ] The adaptive row and durable completion row agree after a course session returns.
- [ ] Reopening Home shows the correct next session.
- [ ] Restarting the app resumes the same active plan from local storage.
- [ ] Sync can hydrate the plan/session rows without generating duplicate local plans.
- [ ] Onboarding creates the first adaptive block before the first Home render.
- [ ] Authentication links the pre-auth route without changing stable IDs.
- [ ] Profile/Settings changes preserve completed work and regenerate only future work.

## 8. Chat-first live-session contract

The active live speaking route is the shared `SessionScreen`; it must render a
conversation, not a persistent tutor portrait. The tutor persona remains a
setting and may appear as a small identity marker in the transcript, but it
must not occupy the center of the live screen.

- The live viewport is an expanded, scrollable two-sided transcript.
- Empty state is explicit: `Your conversation will appear here.`
- Tutor turns appear on the left; learner turns appear on the right.
- Call controls remain below the transcript and never overlap the conversation.
- The saved session writes both the session row and every transcript message.
- `Recent speaking` is derived from persisted completed speaking stages,
  including guided conversation, roleplay, free talk, exam, picture
  description, and pronunciation repair.
- Tapping a recent item opens `SavedSpeakingTranscriptScreen` in read-only
  mode. It must not create an AI call or a new session.
- `Practice again` is the only action that creates a new speaking session from
  saved history.
- The Practice workspace contains both `Course` and `Practice` tabs. Course
  opens the roadmap; Practice remains the mixed-skill workspace and does not
  become speaking-only.
- Universal Speaking Practice also exposes the same Course/Practice switch and
  uses the same persisted recent-history route.
- No current entry point may navigate to the legacy tutor portrait stage,
  Speaking Studio, or the old hardcoded recent roleplay tile.

## 9. Reference screen map

The implemented speaking screens are intentionally split into the same
interaction windows as the approved chat-first reference:

| Reference window | App route | Required interaction |
| --- | --- | --- |
| 1. Speaking setup | `SpeakingPracticeScreen` | Independent mode, topic, level, goal, and duration controls before the live tutor. |
| 2. Speaking Course | `SpeakingHubScreen` → Course | Course/Practice switch and ordered speaking lesson rows. |
| 2. Lesson detail | `SpeakingLessonDetailScreen` | Prompt card, tutor lesson, speaking drill, translation, Start lesson. |
| 3–4. Guided conversation | `SessionScreen` with `speaking_guided` | Tutor and learner transcript bubbles, mic controls, repeat/correction loop. |
| 5. Roleplay catalog | `SpeakingHubScreen` → Practice | Roleplay/Free talk switch, Hot/New/Top today filters, scene cards. |
| 6. Roleplay detail | `SpeakingRoleplayDetailScreen` | Scenario, learner/tutor roles, goal, target phrases, Start roleplay. |
| 7. Roleplay session/result | `SessionScreen` + result | Chat-first turns, live controls, saved transcript, completion and retry. |

The live route is still one shared engine. The new detail/catalog windows are
the missing navigation and content surfaces; they do not create a second AI
session implementation.

## 10. Focused verification commands

Run from `flutter_app`:

```bash
dart format lib/data/database/adaptive_course_store.dart \
  lib/screens/speak/speak_course_activity_screen.dart \
  lib/screens/speak/speak_course_session_screen.dart \
  test/adaptive_course_store_test.dart

flutter test --no-pub \
  test/adaptive_course_store_test.dart \
  test/speak_roadmap_service_test.dart \
  test/speaking_task_plan_test.dart \
  test/live_prompts_test.dart

flutter test --no-pub \
  test/daily_session_completion_test.dart \
  test/tutor_persona_test.dart

git diff --check
```

Do not run `flutter build` during this verification pass. A phone run is still required for final visual/audio QA after the lightweight checks pass.

## 11. Manual phone checklist

1. Complete onboarding and confirm Home shows the adaptive roadmap.
2. Open Practice → Speaking and confirm the independent speaking setup opens with mode, topic, level, goal, and duration controls.
3. Open a Course speaking row and confirm lesson detail appears before Start lesson.
4. Open Practice → Roleplay and confirm catalog → roleplay detail → live chat.
5. Confirm the first tutor introduction appears only within the first three speaking sessions.
6. Confirm the live screen uses the course title/context and the requested A1–B2 level.
7. Complete one guided repeat/correction cycle and return to the course.
8. Confirm the course card/progress updates and the same session does not reset.
9. Open a roleplay anchor and confirm it stays in the scene instead of using guided repeat mode.
10. Complete sessions 1–19 and confirm no second block appears early.
11. Complete session 20, return to Home/Course, and confirm sessions 21–40 appear.
12. Change the learner's level or goal and confirm completed sessions remain while future sessions change.
13. Reopen the app and confirm the current block and speaking progress persist.
14. Open Practice → Recent speaking and confirm the finished session opens its
    saved transcript, with no new live call started.
15. Start a new universal speaking session and confirm the live screen is
    transcript-first with no full-screen tutor portrait.
16. Use Course and Practice tabs from both the Practice workspace and the
    universal Speaking Practice screen.

## 12. Do-not-ship conditions

Stop and fix the flow if any of these occur:

- a course `speaking` item opens Roleplay by default;
- the Practice tab becomes speaking-only;
- the Home screen loses the restored dark dashboard or Practice → Speaking opens the Home dashboard instead of the independent setup;
- a second block appears before all 20 current sessions are complete;
- the next block is missing after session 20;
- a speaking session has no course `contentKey` when launched from Course;
- a completion is visible in one screen but missing after app restart;
- A1 prompts use B1/B2 sentence length or abstraction;
- a profile update rewrites completed history;
- a legacy scene brief becomes reachable from a current entry point.
- the live speaking screen shows a full-body tutor portrait instead of the
  transcript-first layout.
- a recent speaking item starts a new call instead of opening the saved
  transcript.
- guided, picture, or pronunciation sessions disappear from Recent speaking
  because their stage is not indexed.
