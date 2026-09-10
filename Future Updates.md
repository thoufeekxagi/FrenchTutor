# Future Updates

## Purpose

This document describes how the independently tested learning activities will be connected into one personalized, dynamic course.

The immediate release should publish the current fixed course experience with all activities working together. Skill on/off controls are planned for a later update and should not delay publishing.

The final course should feel coherent and personalized without producing identical stories, repeated listening scenes, or unrelated prompts. It should reuse language deliberately while changing the situation, activity, and learner challenge.

## Immediate publishing scope

For the first publishable version:

- Keep the current canonical activity order:
  1. Vocabulary
  2. Reading
  3. Listening
  4. Writing
  5. Speaking
  6. Grammar
- Keep all six activities enabled.
- Continue using the existing independent lesson engines and tested replay, buffering, Live-audio, highlighting, and error-recovery behavior.
- Connect each activity through the adaptive course session and shared unit context.
- Generate the next course content in the background without interrupting the learner.
- Preserve completed lessons as historical records.

The publish version should not introduce a new settings UI or change the tested behavior of the individual activities.

## Future skill settings

Add a separate course-activity settings model. Do not reuse onboarding interests, because interests describe topics while this setting controls which learning activities appear.

The future settings screen will contain one switch for each activity:

- Vocabulary
- Reading
- Listening
- Writing
- Speaking
- Grammar

All six activities are enabled by default. At least one activity must remain enabled.

The canonical order remains stable, but disabled activities are removed from future units. For example:

- All enabled: Vocabulary → Reading → Listening → Writing → Speaking → Grammar
- Grammar disabled: Vocabulary → Reading → Listening → Writing → Speaking
- Reading and Listening disabled: Vocabulary → Writing → Speaking → Grammar

Settings changes affect future and unfinished course content only. Completed lessons remain unchanged. A lesson already in progress should be allowed to finish, while future unstarted slots can be skipped or regenerated under the new configuration.

The setting must be persisted locally and synchronized to the learner account. The course plan fingerprint must include the enabled-activity configuration so a plan created under one configuration is not reused under another.

## Course structure

The course should be modeled as ordered unit slots rather than as an unstructured list of lessons.

Each unit contains:

- A stable situation or theme
- A level-specific learning objective
- A vocabulary bank
- One grammar focus
- One ordered slot for every enabled activity
- A record of generated, ready, completed, skipped, and failed slots

The visible order must be based on unit number and canonical activity position, not on the order in which the learner opens lessons.

If the learner opens Listening before Vocabulary, Listening remains the Listening slot in that unit. It must not move to the top or change the order of future activities.

## Shared unit context

Each unit should have one durable context object used by every activity in that unit.

It should contain:

- Unit topic and situation anchor
- Learner goal and CEFR level
- Unit vocabulary introduced so far
- Vocabulary that should be reviewed
- Grammar pattern for the unit
- Recent completed-session evidence
- Previously used scene and sentence fingerprints
- Activity-specific success criteria

The context should be created once and then passed into each activity generator. Later activities may reuse the unit vocabulary and grammar, but they must produce a new activity rather than copying an earlier lesson.

## Personalization and repetition

Personalization should come from several bounded sources:

1. Learner profile: goal, level, session length, interests, and preferred context.
2. Unit context: the stable situation and current language targets.
3. Learning evidence: completed activities, vocabulary results, corrections, writing feedback, and recent difficulty.
4. Activity contract: the exact format required by Reading, Listening, Writing, Speaking, Vocabulary, or Grammar.

The generation prompt should receive only the relevant, bounded context. It should not receive an unlimited transcript or every previous lesson.

The repetition policy should be explicit:

- Reuse words and useful sentence patterns for retrieval practice.
- Introduce a controlled amount of new language.
- Never copy a previous full sentence, story, dialogue, title, or scene.
- Keep the unit situation coherent across activities.
- Change participants, objects, action, location details, or outcome when the same topic appears again.
- When the topic bank repeats, add a new surface variation and compare against prior fingerprints.

The target balance should be approximately 50% review language and 50% new language, adjusted by CEFR level and learner evidence. This ratio applies to language targets, not to copying the same story setting.

## Generation flow

The generation pipeline should work as follows:

1. Create or load the learner’s current course plan.
2. Select the next unit anchor using the learner goal, level, interests, and topic history.
3. Create the unit context and ordered activity slots.
4. Generate the first activity, normally Vocabulary, and save its targets.
5. Generate later activities using the unit targets and the activity-specific contract.
6. Validate every artifact before marking it ready.
7. Generate images, listening audio, and other enrichment asynchronously without blocking the lesson text.
8. Mark the exact slot ready only after its required artifact is valid.
9. When the learner completes a slot, queue the next missing slot or next unit according to the fixed order.

Generation must remain serialized per learner or per plan. A failed generation must stay attached to its exact slot and must never advance the learner to the next activity.

## Completion and progression

Completion must be idempotent. Repeated callbacks, app restarts, or duplicate taps must not create duplicate lessons or advance the course twice.

The course should distinguish between:

- Opened: the learner viewed the lesson.
- Started: the learner began the activity.
- Completed: the learner satisfied the activity’s completion rule.
- Ready: the artifact is fully generated and validated.

Opening a lesson may justify a small background lookahead, but unit progression should be based on completion. When all enabled slots in a unit are complete, the next unit becomes eligible for generation.

The course UI should always sort by unit and activity order, even when the learner completes activities out of order.

## Validation contracts

Every generator must validate both its own shape and its shared-course requirements.

Shared validation:

- Correct CEFR level
- Correct unit context
- No copied title or scene fingerprint
- No exact repeated target sentence
- Required review/new-language balance
- Valid French and English fields
- No English text accidentally placed in French fields
- No malformed or incomplete artifact

Activity validation:

- Vocabulary has the required number of useful, level-appropriate entries.
- Reading has a valid passage, segments, and checks.
- Listening has valid segments, transcript data, audio generation state, and artwork enrichment state.
- Writing has valid steps, targets, and feedback structure.
- Speaking has valid guided lines and progression.
- Grammar teaches one focused pattern with valid guided or complete steps.

The existing CEFR-specific grammar and activity rules should remain the source of truth. The integration layer should not weaken those rules.

## Future settings behavior

When the skill toggles are introduced:

- Store enabled skills separately from interests.
- Snapshot the enabled order into each new course plan.
- Do not reinterpret old sequence numbers after a settings change.
- Preserve completed lessons and progress.
- Mark unfinished disabled slots as skipped or replaced safely.
- Add newly enabled activities only to future units.
- Prevent the learner from disabling every activity.
- Recalculate the unit size from the enabled activity list.
- Keep generation claims unique by plan, unit, and activity slot.

## Edge cases to cover

- Learner changes settings while a lesson is generating.
- Learner opens activities out of order.
- The app closes during generation or playback.
- The same completion event arrives twice.
- A provider returns malformed JSON.
- Audio or image enrichment fails after the lesson text is ready.
- The learner changes level or goal mid-unit.
- Two devices update the same plan.
- A unit topic repeats after the topic bank is exhausted.
- Vocabulary is disabled but later activities still need safe language targets.
- A generated lesson passes basic validation but repeats a previous scene.

For every case, the rule is to preserve completed history, keep the exact slot identity, retry only the failed work, and never silently reorder the course.

## Implementation phases

### Phase 1: Publish the current course

- Finish Grammar testing.
- Verify the six current activity engines independently.
- Verify the shared adaptive-course artifact path.
- Verify completion creates or prepares the next lesson.
- Verify background image and audio enrichment do not block lesson availability.
- Verify replay, buffering, and Live-session reset behavior across Reading and Listening.

### Phase 2: Add shared unit context

- Introduce a durable unit-level context and target ledger.
- Pass bounded context into every generator.
- Add cross-activity repetition and fingerprint validation.
- Add logs for plan, unit, activity, slot, generation attempt, and validation result.

### Phase 3: Harden progression

- Separate opened, started, completed, and ready states.
- Make completion idempotent.
- Generate slots in canonical order while allowing out-of-order opening.
- Add retry and recovery behavior for failed generation.

### Phase 4: Add activity settings

- Add local and remote profile persistence.
- Add the Settings UI.
- Snapshot enabled activities into new plans.
- Safely migrate unfinished plans when settings change.
- Add tests for every enabled/disabled combination.

### Phase 5: Release validation

- Run deterministic route and store tests.
- Run generator contract tests for every activity and CEFR level.
- Run repetition tests across many units.
- Test account hydration and multi-device synchronization.
- Test the debug harness in both single-skill and full-course modes.
- Only then enable the settings UI for production users.

## Definition of done

The integrated course is ready when a learner can move through multiple units and observe:

- Consistent activity order
- Shared unit context
- Deliberate vocabulary repetition
- New situations and content each time
- No duplicated stories or listening scenes
- Correct CEFR calibration
- Reliable background generation
- Correct completion-driven progression
- Safe recovery after app restarts or failed provider calls
- Completed history preserved after future settings changes

