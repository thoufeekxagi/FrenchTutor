# V3 Rest-of-App Redesign — Master Plan

## Status

Proposal only. No UI implementation is authorized by this document. Each
surface below requires approval before its screen-level code is changed.

The current V3 checkpoint is pushed on branch `ui-redesign-v3` before this
planning pass. Reading, Listening, and Speaking have their own design
contracts. This index covers the remaining product surfaces and the seams
between them.

## Design system contract

The rest of the app should inherit the same V3 language already established by
the current Reading, Listening, Speaking, and Home work:

- Near-black immersive surfaces for focused practice and generated media.
- Warm ivory display type, Inter for controls and learning data, and gold for
  the current action or mastery state.
- One strong primary action per screen; secondary actions use quiet rows or a
  top-right menu.
- Full-width cards with meaningful hierarchy, not a grid of unrelated tiles.
- Every focused flow has a native back action, a stable title, a visible state,
  and a safe bottom action area.
- No hidden content or provider fallback. If content cannot be generated,
  saved, scored, or restored, the screen shows the exact failed state and a
  retry action; it must not silently substitute another lesson or answer.

Shared tokens are currently defined in `lib/design/tokens.dart` and shared
settings behavior is currently split between `SettingsScreen` and
`SpeakSettingsScreen`. Unifying those two is part of this plan, not an
assumption that it is already complete.

## Current product map

```text
Global shell
├── Home                  SpeakingStudioScreen (current dark dashboard)
├── Course                SpeakRoadmapScreen (current speaking-biased roadmap)
├── Practice              SpeakPracticeScreen / LabsScreen (mixed legacy)
└── Photo tutor           ScanScreen

Practice destinations
├── Reading               ReadingLibraryScreen → StoryReaderScreen     [V3 contract exists]
├── Listening             ListeningLabScreen → listening player         [V3 contract exists]
├── Speaking              SpeakingPracticeScreen / SpeakingHubScreen    [V3 contract exists]
├── Vocabulary            VocabPickerScreen / VocabLabScreen / Workshop [needs redesign]
├── Exam                  ExamReadinessScreen / ExamPracticeScreen      [needs redesign]
├── Grammar               GrammarLabScreen / GrammarWorkshopScreen       [legacy shell]
├── Writing               WritingLabScreen / WritingWorkshopScreen       [legacy shell]
├── Pronunciation         Alphabet / Liaison / Connectors labs           [legacy shells]
└── History / Progress    HistoryScreen / ProgressScreen / PathScreen     [needs shell]

Account and support
├── Settings              SettingsScreen + SpeakSettingsScreen           [needs unification]
├── Onboarding            OnboardingScreen + SpeakOnboardingScreen        [shared settings seam]
├── Notes                 NotesReviewScreen                               [needs shell]
├── Subscription          SpeakPaywallScreen                              [needs shell]
└── Photo tutor           ScanScreen + CameraCaptureScreen                 [needs shell]
```

## Implementation order

1. Vocabulary — highest repeat frequency and the foundation for every other
   skill. Freeze the SRS state contract before changing cards.
2. TCF/TEF Exam — create one exam workspace that composes the approved
   Reading, Listening, Speaking, and Writing surfaces without forking them.
3. Course — make the 20-session adaptive plan visible across all four skills,
   then let each course item open the correct focused session.
4. Settings — consolidate learner profile, tutor, study schedule, course
   focus, audio, vocabulary, subscription, account, and support.
5. Practice and the remaining legacy screens — migrate Grammar, Writing,
   History, Progress, Notes, Scan, Auth, Onboarding, and Paywall to the same
   shell one screen at a time.

## Shared navigation rules

```text
Home card / Course item / Practice shortcut
  → one focused destination
  → one saved attempt or completion record
  → one result/review state
  → return to the parent with refreshed progress
```

- A course item always carries `contentKey`, `levelBand`, and `skill`.
- An exam attempt always carries `examName`, `levelBand`, `section`, and
  `attemptId`.
- A vocabulary review always carries a frozen deck ID and the SRS review IDs
  produced by that deck.
- Back navigation never creates a new attempt and never marks incomplete work
  complete.
- Reopening a recent item opens its saved result or transcript; `Practice
  again` is the explicit action that creates a new attempt.

## Shared CEFR rules

The selected level is a hard content contract, not decorative metadata.

| Level | Content ceiling | Interaction expectation |
| --- | --- | --- |
| A1 | concrete nouns, greetings, basic present tense, short clauses | model → one small response → immediate correction |
| A2 | familiar daily situations, simple past/future, short explanations | guided production with light prompts |
| B1 | connected ideas, reasons, comparisons, everyday register | independent response plus targeted coaching |
| B2 | nuance, register, argument, reformulation, complex connectors | performance under realistic constraints |

Generation, examples, scoring copy, and review hints must all use the same
`levelBand`. A1 must never receive B1/B2 abstraction merely because a topic is
interesting.

## Failure contract

```text
request starts
  → loading state with the exact target (deck / exam task / course item)
  → success: persist first, then render
  → failure: show the provider/storage/scoring error
             [Retry] [Back]
```

There is no hidden alternate provider, synthetic replacement content, or
legacy route behind a failed request. A plan document may propose a second
explicit user action later, but it is not a fallback.

## Acceptance gate for the whole redesign

- [ ] Home remains Home. No redesigned Practice, Speaking, or Exam UI is
      injected into the global Home tab.
- [ ] Practice remains a mixed-skills hub; it does not become speaking-only.
- [ ] Course exposes the adaptive 20-session sequence and the skill attached
      to every item.
- [ ] Vocabulary, Exam, Course, and Settings each have one canonical route.
- [ ] Existing Reading, Listening, and Speaking routes remain their own
      focused destinations and are composed rather than duplicated.
- [ ] Every generated or scored result has a durable local identity and a
      visible error state.
- [ ] Static checks pass before any phone visual pass.
- [ ] The user approves each screen-level proposal before implementation.

## Source references

Current local contracts:

- `V3 design/reading practice redesign.md`
- `V3 design/listening spotify wireframes.md`
- `V3 design/speaking end-to-end verification.md`
- `lib/design/tokens.dart`
- `lib/screens/main_tab_screen.dart`

