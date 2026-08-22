# V3 Vocabulary — Library, Review, and Retrieval Wireframes

## Status

Proposal only. Vocabulary is the first remaining screen family to implement
after approval.

## Product contract

Vocabulary is not just a flashcard list. It is a short retrieval loop that
turns course words into usable French:

```text
Vocabulary home
  → choose Due review / Course words / Topic set
  → freeze a review deck
  → preview → hear → recall → context → produce
  → grade each evidence point
  → save SRS state and review history
  → show weak words and next due date
```

The same `VocabEntry.id` must identify a word in bundled curriculum,
generated sets, course activities, reading keywords, listening words, and the
SRS store. A generated set is content; the learner's review state is separate
and must not be overwritten when a set is regenerated.

## Current code and gaps

Current surfaces:

- `lib/screens/pathway/vocab_picker_screen.dart` — choose automatic or
  generated vocabulary.
- `lib/screens/labs/vocab_lab_screen.dart` — older vocabulary lab/library.
- `lib/screens/lessons/vocabulary_workshop_screen.dart` — already has the
  strongest behavior: Preview, Learn, Recall, Context, Use, Done.
- `lib/screens/lessons/flashcard_session_screen.dart` — separate SRS card
  flow with a different shell.
- `lib/services/srs_service.dart`, `lib/models/srs_state.dart` — review state
  and grading.
- `lib/data/database/generated_vocabulary_set_store.dart` — persisted learner
  sets and cover metadata.

Current problems to solve in the redesign:

1. The learner can enter several vocabulary surfaces with different visual
   shells and no obvious distinction between a library set and a due-review
   queue.
2. The workshop contains useful stages but hides the deck identity and due
   impact from the learner.
3. The current workshop contains hidden content substitutions when context
   generation fails. The new contract must show the failure and stop that
   word's context step until the user retries.
4. There is no single recent-result card that tells the learner what changed:
   recalled, missed, new, and next due.

## Visual thesis

Use the dark V3 learning shell with one large “today's review” action, quiet
word rows, and a calm focused card. The word is the hero; decoration never
competes with pronunciation or meaning.

## Screen 1 — Vocabulary home

```text
┌──────────────────────────────────────┐
│ ‹  Vocabulary                     ⋯  │
│                                      │
│ Build words you can use              │
│ French words from your course,      │
│ stories, and conversations.          │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ TODAY'S REVIEW                  │ │
│ │ 12 words due · 4 need attention │ │
│ │ [Start review →]                │ │
│ └──────────────────────────────────┘ │
│                                      │
│ YOUR COLLECTION                      │
│ [Course words] [Saved words]         │
│ [Topic sets]                         │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Course words                     │ │
│ │ Unit 03 · Daily routine         │ │
│ │ 18 / 24 ready      Continue ›   │ │
│ ├──────────────────────────────────┤ │
│ │ Saved from Reading               │ │
│ │ The Garden Key · 7 words        │ │
│ │ Review set                         │
│ └──────────────────────────────────┘ │
│                                      │
│ BROWSE BY TOPIC                      │
│ [Travel] [Food] [Home] [Work]        │
└──────────────────────────────────────┘
```

Interactions:

- `Start review` uses the due queue and creates a frozen `reviewDeckId`.
- `Course words` opens the current course unit, not a random generated set.
- `Saved words` filters the same vocabulary library by source.
- Topic chips filter; they do not silently start a review.
- The overflow menu contains only import/export/report and vocabulary
  settings; global Settings remains in the shared app shell.

## Screen 2 — Set detail / deck preview

```text
┌──────────────────────────────────────┐
│ ‹  Course words                   ♡  │
│                                      │
│ DAILY ROUTINE                        │
│ A1 · 24 words · from Unit 03         │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ 18 ready   4 learning   2 new    │ │
│ │ ────────────────●─────────────── │ │
│ └──────────────────────────────────┘ │
│                                      │
│ WORDS IN THIS SET                    │
│ 🔊 bonjour       hello          ›   │
│ 🔊 travailler     to work        ›   │
│ 🔊 demain         tomorrow       ›   │
│ 🔊 rendez-vous    appointment    ›   │
│                                      │
│ [Review due · 12]  [Practice all]    │
└──────────────────────────────────────┘
```

Tapping a row opens the word detail without changing SRS state. The review
buttons are the only actions that create a deck.

## Screen 3 — Word detail

```text
┌──────────────────────────────────────┐
│ ‹  Word                         ⋯   │
│                                      │
│              🔊                       │
│           travailler                 │
│           /tʁa.va.je/                │
│                                      │
│           to work                    │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Je travaille à Montréal.     🔊  │ │
│ │ I work in Montreal.              │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Verb · regular -er                   │
│ Related: travail · travailleur      │
│                                      │
│ [Save word]    [Practice this word]  │
└──────────────────────────────────────┘
```

The exact bundled/generated example is displayed if it exists. If an example
must be generated, loading and failure are explicit; the UI does not invent a
placeholder sentence and present it as verified content.

## Screen 4 — Guided review card

```text
┌──────────────────────────────────────┐
│ ×  Review · 03 / 12              ⋯  │
│ ─────────────●────────────────────  │
│                                      │
│              What is this?           │
│                                      │
│             travailler               │
│               🔊                     │
│                                      │
│           [Show meaning]             │
│                                      │
│        I work in Montreal.           │
│        Je travaille à Montréal.      │
│                                      │
│  [Again] [Hard] [Good] [Easy]        │
│                                      │
│  Tap a word for meaning · Hold 🔊    │
└──────────────────────────────────────┘
```

Behavior:

1. The French word is shown first for recognition/production according to the
   deck mode.
2. `Show meaning` reveals English, phonetic text, and the example.
3. Audio is a direct action and never blocks grading.
4. A grade writes `SRSState` and an append-only review record before advancing.
5. Leaving mid-deck preserves the deck cursor and does not grade the current
   word.

## Screen 5 — Context check

```text
┌──────────────────────────────────────┐
│ ‹  Context · 03 / 12                 │
│                                      │
│ Choose the sentence that fits:       │
│                                      │
│ Je ___ à Montréal.                   │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ travaille                       │ │
│ ├──────────────────────────────────┤ │
│ │ voyage                          │ │
│ ├──────────────────────────────────┤ │
│ │ dors                            │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [Check answer]                       │
│                                      │
│ Correct: explain the choice in one  │
│ short A1 sentence.                  │
└──────────────────────────────────────┘
```

The selected answer is not graded until `Check answer`. A wrong answer shows
the correct answer, a short level-appropriate explanation, and a retry path.

## Screen 6 — Use it

```text
┌──────────────────────────────────────┐
│ ‹  Use it · 03 / 12                  │
│                                      │
│ Say or write one sentence with:      │
│ travailler · to work                │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Write in French…                │ │
│ └──────────────────────────────────┘ │
│ [Record]              [Check]        │
│                                      │
│ Your feedback                       │
│ ✓ Word used correctly                │
│ • One small correction               │
│                                      │
│ [Try again]          [Next word →]   │
└──────────────────────────────────────┘
```

For a speaking-enabled word, `Record` opens the shared speaking capture and
returns a pronunciation/result object. It must not create a second vocabulary
deck. `Check` is a production evidence point, not an essay grader.

## Screen 7 — Review result

```text
┌──────────────────────────────────────┐
│ ‹  Review complete                   │
│                                      │
│             12 words                 │
│       8 ready · 3 learning · 1 new   │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ NEXT REVIEW                      │ │
│ │ 8 words tomorrow · 4 in 3 days  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Needs another pass                   │
│ travailler · demain                  │
│                                      │
│ [Review missed words]                │
│ [Back to Vocabulary]                 │
└──────────────────────────────────────┘
```

## Data and persistence contract

```text
VocabEntry.id
  → reviewDeck(id, source, levelBand, createdAt, cursor)
  → reviewEvidence(id, recall, context, production, pronunciation?)
  → SRSState(entryId, ease, interval, reps, dueAt, lastGrade)
  → reviewResult(deckId, counts, completedAt)
```

- The deck is frozen at start; new course content cannot reorder an active
  review.
- A partial review stores cursor and evidence but not completion.
- A completed review is available from Vocabulary home and History.
- Generated sets sync through the existing generated-set store; SRS review
  records sync separately.
- Delete or regenerate a set does not delete the learner's historical review
  evidence for the same `VocabEntry.id`.

## Edge cases

- Empty due queue: show `You are caught up` and offer Course words or a topic
  set; do not create a zero-word deck.
- Generated set with zero usable entries: show a blocking error and return to
  the library; do not open Workshop.
- Audio unavailable: show the audio error on the word; the word remains
  gradeable only if the user explicitly chooses a text-only action.
- Context generation fails: show `Context unavailable` with Retry; do not use
  a canned sentence.
- App closes mid-review: resume from saved cursor and deck ID.
- Level changes mid-review: finish the frozen deck at its original level; new
  decks use the new level.

## Mobbin references

These are references for interaction patterns, not artwork or copy to clone:

- [Duolingo translate-the-words card](https://mobbin.com/screens/825f56d8-92e5-48b1-9d1f-a09a2986c08e) — focused single-task card with progress.
- [Duolingo word practice list](https://mobbin.com/screens/946faf6e-343e-4454-906e-c624272e8902) — scan-friendly word rows with audio and status.
- [Vocabulary result list](https://mobbin.com/screens/09632393-abdf-4476-88d9-52fabb059b70) — useful result/review grouping with save and audio actions.
- [Babbel learning-plan home](https://mobbin.com/screens/fdaa7267-a4f1-4088-a90a-d1a9611fa63a) — “learn now” and “review now” separated by intent.

## Acceptance checklist

- [ ] One canonical Vocabulary entry point from Practice.
- [ ] Due review, Course words, and generated topic sets are visibly distinct.
- [ ] Review deck identity and cursor survive app restart.
- [ ] Every grade writes SRS state before the next card appears.
- [ ] Result screen shows what changed and what is due next.
- [ ] A1 examples and feedback stay short and concrete; A2/B1/B2 scale by
      the shared CEFR contract.
- [ ] No hidden fallback content is used for missing examples, audio, or
      scoring.
- [ ] Recent vocabulary opens the saved result; `Practice again` creates a
      fresh deck.
