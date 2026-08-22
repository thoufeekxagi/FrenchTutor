# V3 Course — Adaptive Path, Unit, and Lesson Wireframes

## Status

Proposal only. This document is the contract for the global Course tab and
the course-to-skill handoff.

## Product contract

Course is the learner's long-term path. It is not the Speaking Home and must
not be replaced by a speaking-only roadmap.

```text
Course tab
  → current language / level / goal
  → continue next course item
  → unit list with 20-session adaptive block
  → lesson detail
  → focused skill session (Reading / Listening / Speaking / Writing / Vocab)
  → skill result
  → course activity evidence
  → adaptive completion + next item
```

The adaptive course owns ordering and completion. Each skill owns its own
lesson interaction and result. The handoff must always carry:

```text
contentKey · blockIndex · blockPosition · levelBand · primarySkill · unit
```

## Current code and gaps

- `lib/screens/speak/speak_roadmap_screen.dart` currently renders the Course
  tab and is strongly speaking-branded.
- `lib/data/database/adaptive_course_store.dart` owns 20-session blocks,
  stable content keys, profile changes, and completion.
- `lib/screens/speak/speak_course_activity_screen.dart` shows a course item
  activity list.
- `lib/screens/speak/speak_course_session_screen.dart` records course skill
  progress and completion.
- `lib/services/course_progress_service.dart` stores activity evidence.
- `lib/screens/path/path_screen.dart` separately renders a competency map.

The current contract is strong for adaptive sequencing, but the visual and
navigation ownership are still split. The Course tab must expose all learning
skills, while Speaking remains its own Practice destination.

## Visual thesis

Use the V3 dark shell with one “Continue” hero, a compact level/goal context
row, and a vertical unit path. Each unit is a section with a clear current
item and small evidence markers; it should feel like a path, not a dashboard
grid.

## Screen 1 — Course home

```text
┌──────────────────────────────────────┐
│ Course                         ⚙   │
│ French · A2 · TEF Canada             │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ CONTINUE                         │ │
│ │ Make a useful choice              │ │
│ │ Unit 02 · Vocabulary + speaking  │ │
│ │ 6 min · A2                       │ │
│ │ [Continue →]                     │ │
│ └──────────────────────────────────┘ │
│                                      │
│ BLOCK 1 · 1–20                       │
│ 7 of 20 sessions complete            │
│ ─────────────●────────────────────  │
│                                      │
│ UNIT 01 · FOUNDATIONS                │
│ ✓ Greetings and introductions        │
│ ✓ Everyday objects                   │
│                                      │
│ UNIT 02 · DAILY ROUTINES             │
│ ┌──────────────────────────────────┐ │
│ │ 08  Talk about your routine      │ │
│ │     Speaking · A2 · 10 min   ›  │ │
│ ├──────────────────────────────────┤ │
│ │ 09  Read a morning note          │ │
│ │     Reading · A2 · 5 min     ›  │ │
│ ├──────────────────────────────────┤ │
│ │ 10  Review routine words         │ │
│ │     Vocabulary · A2 · 6 min  ›  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ NEXT BLOCK                         › │
└──────────────────────────────────────┘
```

The current session is visibly different from completed and locked sessions.
The user can open any completed item for review; a future locked item opens a
short explanation, not a dead tap.

## Screen 2 — Unit detail

```text
┌──────────────────────────────────────┐
│ ‹  Unit 02 · Daily routines          │
│ A2 · 6 sessions · 42 min             │
│                                      │
│ TALK ABOUT YOUR ROUTINE              │
│ Use time, frequency, and simple      │
│ reasons in everyday French.          │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ 08 · Speaking                    │ │
│ │ Guided conversation              │ │
│ │ ● Current · 0 / 3 checks        │ │
│ │ [Open lesson →]                 │ │
│ └──────────────────────────────────┘ │
│                                      │
│ 09 · Reading                         │
│ 10 · Vocabulary                       │
│ 11 · Listening                        │
│ 12 · Writing                          │
│ 13 · Review                           │
│                                      │
│ [Start current lesson]               │
└──────────────────────────────────────┘
```

Unit detail explains the skill rotation and the goal of the unit. It does not
create a second content generator.

## Screen 3 — Lesson detail / handoff

```text
┌──────────────────────────────────────┐
│ ‹  Course lesson                ⋯   │
│                                      │
│ 08 · SPEAKING · A2                   │
│ Talk about your routine              │
│                                      │
│ A short guided conversation about    │
│ what you do on a normal day.        │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ TODAY'S EVIDENCE                 │ │
│ │ Hear it · say it · repair it     │ │
│ │ 3 guided checks · 10 minutes     │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Before you start                     │
│ Target phrases                       │
│ • Je me lève à…                     │
│ • D'habitude, je…                   │
│ Vocabulary · 5 words                │
│                                      │
│ [Start speaking →]                  │
└──────────────────────────────────────┘
```

The primary action is selected from `primarySkill`. For a Listening item it
opens the approved Listening library/player; for Vocabulary it opens the
approved vocabulary workshop; for Speaking it opens the approved
chat-first route. The course item never opens a generic legacy screen.

## Screen 4 — Completion handoff

```text
┌──────────────────────────────────────┐
│ Course progress                      │
│                                      │
│ ✓ Lesson complete                    │
│ Talk about your routine              │
│                                      │
│ Evidence saved                       │
│ Speaking  ✓  Vocabulary  ✓           │
│ Time practiced · 08:42               │
│                                      │
│ Next in your path                    │
│ Read a morning note · Reading · 5m   │
│                                      │
│ [Continue path →] [Review lesson]    │
└──────────────────────────────────────┘
```

Completion is written before this screen renders. `Review lesson` opens the
saved result/transcript. `Continue path` opens the next stable `contentKey`.

## Screen 5 — Block transition after session 20

```text
┌──────────────────────────────────────┐
│ Your next block                      │
│                                      │
│ Block 1 complete · 20 / 20           │
│                                      │
│ You built evidence across:           │
│ Reading · Listening · Speaking       │
│ Vocabulary · Grammar · Writing       │
│                                      │
│ BLOCK 2 · NEXT 20 SESSIONS           │
│ Calibrated to A2 · TEF Canada        │
│                                      │
│ [Open next block]                    │
└──────────────────────────────────────┘
```

The second block is appended only after all 20 current sessions are complete.
Profile changes preserve completed content keys and regenerate only future
sessions, as already specified in `speaking end-to-end verification.md`.

## Data contract

```text
AdaptiveCoursePlan
  profileSnapshot, planVersion, blockIndex, sessions[1..20]

AdaptiveCourseSessionSpec
  contentKey, sequence, blockIndex, blockPosition, unit,
  title, subtitle, primarySkill, levelBand, duration,
  completionState, courseEvidenceId

CourseActivityProgress
  contentKey, skills, seconds, completedAt
```

- Plan hydration happens before Course renders.
- A session tap never regenerates the plan.
- Skill result and course activity are linked by `contentKey`.
- Failed generation leaves the item `blocked` with a visible error and retry;
  it does not mark the item complete or route to another skill.
- Completing a lesson refreshes Home, Course, and the relevant Practice
  surface without changing global Home ownership.

## Mobbin references

- [Duolingo course sections](https://mobbin.com/screens/a9ae901c-0f55-4e44-8685-2abb506fb08c) — reference for a calm vertical course path and section progress.
- [Duolingo early course path](https://mobbin.com/screens/82371c0c-d233-45af-9fc7-26f96c2cde8f) — reference for current section versus locked future content.
- [Babbel learning plan](https://mobbin.com/screens/fdaa7267-a4f1-4088-a90a-d1a9611fa63a) — reference for Continue learning and Review now as separate intentions.
- [Duolingo course flow](https://mobbin.com/flows/047e252c-3bf3-4c33-b3b2-c5dd6065d1d4) — reference flow for course → unit → activity.

## Acceptance checklist

- [ ] Global Course is no longer speaking-only.
- [ ] Home, Course, Practice, and Speaking Home remain independent routes.
- [ ] Every item shows level, skill, duration, and completion state.
- [ ] Course item → lesson detail → focused skill → result → next item works
      with one stable `contentKey`.
- [ ] Sessions 1–20 are visible and sessions 21–40 appear only after the
      first block is complete.
- [ ] Profile changes preserve completed sessions and recalibrate future ones.
- [ ] Locked, failed, in-progress, completed, and reviewed states are all
      represented.
- [ ] No course item silently opens a legacy generator or a generic fallback.
