# V3 Practice Hub and Remaining Screens — Migration Plan

## Status

Proposal and inventory. This document does not authorize implementation of all
listed screens at once. The implementation order is one screen family at a
time after the core Vocabulary, Exam, Course, and Settings proposals are
approved.

## Screen inventory

| Priority | Current surface | Current route/code | Direction |
| --- | --- | --- | --- |
| P0 | Practice hub | `LabsScreen`, `SpeakPracticeScreen` | One mixed-skills hub; no speaking-only takeover |
| P1 | Grammar | `GrammarLabScreen`, `GrammarWorkshopScreen` | Reuse Vocabulary/Reading shell with rule → example → production |
| P1 | Writing | `WritingLabScreen`, `WritingWorkshopScreen`, `WritingTaskScreen` | Prompt → draft → feedback → saved submission |
| P1 | Progress/path | `ProgressScreen`, `PathScreen`, `HistoryScreen` | One evidence-led progress surface with filters |
| P2 | Notes | `NotesReviewScreen` | Saved notes grouped by source and word/lesson |
| P2 | Onboarding | `OnboardingScreen`, `SpeakOnboardingScreen` | One profile setup feeding shared Settings and Course |
| P2 | Photo tutor | `ScanScreen`, `CameraCaptureScreen` | Scan result → tutor explanation → save to Practice |
| P2 | Subscription | `SpeakPaywallScreen` | Product truth, clear plan state, no fake unlocks |
| P3 | Labs | Alphabet, Liaison, Connectors, Listening, Roleplay labs | Convert to typed Practice cards or focused skill routes |
| P3 | Auth/support | `AuthScreen`, `SpeakAuthScreen`, product guide | One auth shell and one support/content shell |

The old roleplay-specific lab should not regain ownership of Speaking. It
should deep-link to the approved Speaking Practice catalog.

## Practice hub contract

Practice is the place for a deliberate skill session. It is not Home, Course,
Speaking Home, or a general list of every internal lab.

```text
Practice
  → continue the recommended skill
  → choose a skill family
  → choose a mode/topic in a sheet or compact picker
  → focused session
  → result/review
  → return to Practice with evidence
```

## Screen 1 — Practice hub

```text
┌──────────────────────────────────────┐
│ Practice                         ⚙   │
│ Choose one skill. Leave with evidence│
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ NEXT PRACTICE                    │ │
│ │ Review routine vocabulary        │ │
│ │ 5 words · 6 min · A2             │ │
│ │ [Continue →]                     │ │
│ └──────────────────────────────────┘ │
│                                      │
│ SKILLS                              │
│ [Speaking] [Listening] [Reading]    │
│ [Vocabulary] [Writing] [Grammar]    │
│ [Exam preparation]                  │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Vocabulary                       │ │
│ │ 12 words due · 4 need attention │ │
│ │ Start review                    ›│ │
│ ├──────────────────────────────────┤ │
│ │ Speaking                         │ │
│ │ Guided conversation · A2        │ │
│ │ Choose a mode                   ›│ │
│ ├──────────────────────────────────┤ │
│ │ Exam preparation                 │ │
│ │ TCF Canada · A2 · next: Listening│ │
│ │ Continue                         ›│ │
│ └──────────────────────────────────┘ │
│                                      │
│ RECENT                               │
│ Listening result · 7/10          ›  │
└──────────────────────────────────────┘
```

The skill chips are entry filters, not nine separate visual styles. Each card
shows a real next action from persisted state.

## Screen 2 — Grammar lesson contract

```text
┌──────────────────────────────────────┐
│ ‹  Grammar · A2                 ⋯  │
│                                      │
│ THE PAST WITH AVOIR                  │
│ Rule → example → use it              │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ J'ai parlé.                      │ │
│ │ I spoke.                         │ │
│ │ avoir + past participle          │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Try it                              │
│ Choose the sentence that is correct. │
│ [choice] [choice] [choice]           │
│                                      │
│ [Check]                     02 / 05  │
└──────────────────────────────────────┘
```

Grammar should use the same focused state pattern as Vocabulary: a compact
progress rail, one concept at a time, one answer state, and a saved result.

## Screen 3 — Writing lesson contract

```text
┌──────────────────────────────────────┐
│ ‹  Writing · A2                 ⋯  │
│                                      │
│ DESCRIBE A PAST EVENT                │
│ Everyday French · 10 min             │
│                                      │
│ Prompt                               │
│ Write 80–100 words about a recent    │
│ day trip. Use three time markers.    │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Start writing in French…        │ │
│ │                                  │ │
│ └──────────────────────────────────┘ │
│ 42 / 100 words       Save draft     │
│                                      │
│ [Submit for feedback]               │
└──────────────────────────────────────┘
```

The submission and feedback are durable. Leaving saves a draft; it does not
submit or mark the course item complete.

## Screen 4 — Progress and history

```text
┌──────────────────────────────────────┐
│ Progress                         ⋯  │
│ French · A2 · TEF Canada             │
│                                      │
│ THIS WEEK                            │
│ 4 sessions · 32 min · 18 words      │
│ ─────────────●────────────────────  │
│                                      │
│ EVIDENCE                             │
│ Speaking        Building             │
│ Listening       Building             │
│ Vocabulary      Ready                │
│ Writing         New                  │
│                                      │
│ RECENT                              │
│ Routine words · Vocabulary       ›  │
│ Appointment · Speaking           ›  │
│ TCF listening · 7 / 10           ›  │
└──────────────────────────────────────┘
```

`ProgressScreen`, `HistoryScreen`, and the competency `PathScreen` should
eventually share a data presentation layer. They may retain different deep
links, but tapping evidence always opens saved material rather than starting
new content.

## Screen 5 — Onboarding handoff

```text
┌──────────────────────────────────────┐
│ FrenchTutor                    02 / 04│
│                                      │
│ Set your starting point              │
│                                      │
│ Level    [A1] [A2] [B1] [B2]         │
│ Goal     [Everyday] [TEF] [Work]     │
│ Time     [3 min] [10 min] [20 min]   │
│                                      │
│ Your first block includes Reading,  │
│ Listening, Speaking, Vocabulary,    │
│ Grammar, and Writing.                │
│                                      │
│ [Create my path →]                  │
└──────────────────────────────────────┘
```

There is one onboarding profile writer. A speaking introduction may be the
first session, but onboarding must create the same adaptive Course block and
shared Settings values used by returning users.

## Screen 6 — Photo tutor handoff

```text
┌──────────────────────────────────────┐
│ ‹  Photo tutor                       │
│                                      │
│ [ camera / captured image ]          │
│                                      │
│ What do you want to do?              │
│ [Name objects] [Explain grammar]     │
│ [Make a vocabulary set]              │
│                                      │
│ [Ask Murray]                         │
└──────────────────────────────────────┘
```

The scan result must identify its saved source image, prompt, response, and
created vocabulary set. A failed vision request stays on this screen with an
error and retry.

## Shared migration rules

- Do not redesign all labs in one commit.
- First replace the Practice hub shell while preserving destinations.
- Then migrate one focused family at a time to its approved contract.
- Keep old routes only while an explicit redirect exists and no current entry
  point reaches the old shell.
- Avoid new dependencies; use `DesignTokens`, existing stores, and existing
  `AppRouter` patterns.
- Each screen family gets a targeted test and a static source check before a
  phone visual pass.

## Acceptance checklist

- [ ] Practice contains Speaking, Listening, Reading, Vocabulary, Writing,
      Grammar, and Exam without becoming a Speaking screen.
- [ ] Practice cards reflect persisted next actions, not hardcoded legacy
      content.
- [ ] Grammar and Writing have explicit draft/result states.
- [ ] Progress and History open saved evidence rather than starting sessions.
- [ ] Onboarding writes the same profile, Settings, and Course contracts.
- [ ] Photo tutor stores source/context/results or shows a visible failure.
- [ ] Legacy lab routes are either migrated or explicitly redirected.
- [ ] Home remains untouched by this Practice redesign.

