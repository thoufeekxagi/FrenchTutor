# V3 Settings — Profile, Tutor, Learning, and Account Wireframes

## Status

Proposal only. Settings is a shared infrastructure screen; it should be
redesigned after Vocabulary, Exam, and Course contracts are approved so its
controls name real product behavior.

## Product contract

Settings answers four questions without becoming a wall of switches:

1. Who am I learning as? — language, level, goal, tutor.
2. How do I want to practice? — focus, schedule, pace, audio, vocabulary.
3. What access do I have? — subscription and usage.
4. How do I manage my account? — support, legal, sign out, delete.

There is one canonical Settings route. Reading, Listening, Speaking, and
Exam may open a scoped settings sheet, but a scoped sheet writes to the same
settings services and closes with the same `Done` action.

## Current code and gaps

- `lib/screens/settings/settings_screen.dart` is a large, scrollable surface
  containing profile, learning goal, session length, course focus, schedule,
  tutor, roadmap, lesson voice, vocabulary practice, notetaker, subscription,
  account, and support.
- `lib/screens/speak/speak_settings_screen.dart` is a separate Speaking
  settings surface and route.
- `lib/screens/onboarding/onboarding_screen.dart` and
  `lib/screens/onboarding/speak_onboarding_screen.dart` capture overlapping
  profile/tutor preferences.
- `lib/services/session_settings.dart`, `TutorTuning`, and profile storage
  are the persistence seams that must remain authoritative.

Current gaps:

1. The user can encounter different shells and different vocabulary for the
   same setting depending on entry point.
2. High-impact learner settings and account/destructive actions are not
   visually separated enough.
3. Tutor changes need a clear “next session” rule; a live session must not
   change persona halfway through.
4. Debug-only controls must never appear in a release build or be mixed with
   learner controls.

## Visual thesis

Use the dark V3 shell with a calm profile header, grouped rows, and compact
value summaries. Edit choices in sheets or inline pickers. Preserve the
existing gold accent and the Reading-style `Done` action for scoped sheets.

## Screen 1 — Settings home

```text
┌──────────────────────────────────────┐
│ ‹  Settings                          │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ THOUFEEK                         │ │
│ │ French · A2 · TEF Canada         │ │
│ │ Tutor Murray · Balanced          ›│ │
│ └──────────────────────────────────┘ │
│                                      │
│ LEARNING                             │
│ Level                         A2  ›  │
│ Goal                     TEF Canada ›│
│ Course focus          All six skills ›│
│ Study schedule        Mon–Fri  ›    │
│                                      │
│ TUTOR & AUDIO                        │
│ Tutor persona          Murray     ›  │
│ English / French mix     Balanced  › │
│ Speaking pace            Natural   › │
│ Lesson narration         1×       ›  │
│                                      │
│ PRACTICE                             │
│ Vocabulary queue          5 words ›  │
│ Notetaker                   On     ›  │
│                                      │
│ ACCESS                              │
│ Plan · Free / Pro                  ›  │
│                                      │
│ ACCOUNT & SUPPORT                   │
│ Help · Feedback · Legal             ›  │
│ Sign out                              │
└──────────────────────────────────────┘
```

The first viewport shows identity and learning state. Subscription is visible
but not allowed to dominate. Destructive actions stay below a divider.

## Screen 2 — Learner profile sheet

```text
┌──────────────────────────────────────┐
│ Learner profile                 Done │
│                                      │
│ LANGUAGE                             │
│ Learning French                      │
│                                      │
│ LEVEL                                │
│ [A1] [A2] [B1] [B2]                 │
│ A2 · Elementary                      │
│ Everyday situations and short       │
│ explanations.                       │
│                                      │
│ GOAL                                │
│ [TEF Canada ▾]                      │
│                                      │
│ Changing level changes future        │
│ content. Completed work stays saved. │
└──────────────────────────────────────┘
```

Changing level requires confirmation. The sheet writes profile data and marks
future adaptive course work for recalibration; it never rewrites completed
sessions or an active attempt.

## Screen 3 — Tutor and audio sheet

```text
┌──────────────────────────────────────┐
│ Tutor & audio                   Done │
│                                      │
│ YOUR TUTOR                           │
│ ┌────────┐  Murray                   │
│ │  icon  │  French conversation tutor│
│ └────────┘  [Preview voice]          │
│                                      │
│ English / French mix                 │
│ [Gentle] [Balanced] [Immersion]      │
│                                      │
│ Speaking pace                        │
│ [Slower] [Natural] [Faster]          │
│                                      │
│ Lesson narration                     │
│ ─────────●──────────  1.0×           │
│                                      │
│ Applies from the next session.      │
└──────────────────────────────────────┘
```

The active live session retains the persona and pace it started with. New
sessions read the updated settings.

## Screen 4 — Scoped player settings

Reading, Listening, Exam, and Speaking may open a smaller sheet:

```text
┌──────────────────────────────────────┐
│ Practice settings               Done │
│                                      │
│ Show translation                 Off │
│ Highlight current word           On │
│ Text size                    Medium │
│ Playback speed                    1× │
│                                      │
│ Open all Settings                 ›  │
└──────────────────────────────────────┘
```

The scoped sheet does not create a second preference store. It reads/writes
the shared settings service and returns to the same parent state.

## Screen 5 — Subscription and account

```text
┌──────────────────────────────────────┐
│ ‹  Account & access                  │
│                                      │
│ PLAN                                │
│ Pro · Renews Aug 31                  │
│ [Manage subscription]                │
│                                      │
│ ACCOUNT                             │
│ Name        Thoufeek                 │
│ Email       thoufeek…                │
│ Signed in with Apple                 │
│                                      │
│ SUPPORT                             │
│ Feedback                             │
│ Privacy policy                       │
│ Terms of service                     │
│                                      │
│ Sign out                             │
│ Delete account                       │
└──────────────────────────────────────┘
```

Delete requires a destructive confirmation and an explicit account identity
check. Subscription status remains server-authoritative where available; a
network error is shown as an access-status error, never as a guessed plan.

## Settings data contract

```text
Profile
  language, level, goal, interests, sessionLength, reminderTime

TutorTuning
  persona, languageMix, voiceSpeed, narrationRate

PracticePreferences
  autoQueueSize, practicePassesPerWord, notetakerEnabled

AccessState
  entitlement, renewal, remainingSeconds, serverAuthoritative
```

- Each row displays the persisted value after a successful write.
- If a write fails, keep the old value visible and show the exact error with
  Retry; do not optimistically pretend the setting changed.
- Profile updates notify Home, Course, Practice, Vocabulary, Exam, Reading,
  Listening, and Speaking through their existing stores/providers.
- A running live session snapshots tutor settings at start.
- Debug/orchestration controls remain behind `kDebugMode` and never enter the
  learner-facing wireframe.

## Mobbin references

- [Babbel Settings](https://mobbin.com/screens/b877ba12-853e-43ea-a73e-243d76840c2d) — grouped account/settings rows with a quiet dark shell.
- [Babbel Profile summary](https://mobbin.com/screens/65435f22-30a8-440c-9868-8fb64d41c7e9) — useful weekly summary and Continue learning action.
- [Duolingo course settings/profile surface](https://mobbin.com/screens/64ee7bc1-2fbd-4f2d-a5e1-8c27805ba882) — reference for separating profile and learning controls.

## Acceptance checklist

- [ ] One canonical Settings destination; Speaking settings is a scoped entry
      or redirect, not a second preference architecture.
- [ ] First viewport shows profile, language, level, goal, and tutor summary.
- [ ] Level changes are confirmed and affect future content only.
- [ ] Tutor/audio changes apply on the next session and never mutate an active
      call.
- [ ] Scoped Reading/Listening/Speaking sheets reuse shared state and close
      with `Done`.
- [ ] Account, subscription, support, sign-out, and delete are clearly
      separated from learning controls.
- [ ] Failed writes remain visible and retryable; no optimistic lie is shown.
- [ ] Debug controls are absent from the learner-facing release layout.

