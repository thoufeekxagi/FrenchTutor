# Vocabulary V4 — pure flashcards

Status: fresh proposal only. This deliberately replaces the previous
Vocabulary V3 direction. No application code is changed.

## Scope boundary

Vocabulary is now one focused product:

- choose a vocabulary set;
- answer flashcards;
- see whether the answer was correct;
- continue until the short set is complete.

Speaking, listening, reading, writing, grammar, tutor calls, and cross-skill
mode selection belong in the separate Review/Practice area. They do not appear
inside Vocabulary.

## The core interaction

The learner should never be asked to grade themselves. Each flashcard presents
one objective recall task with three French choices. The app knows the answer,
marks the response immediately, and schedules the word automatically.

```text
English meaning + memorable image
              ↓
        choose one answer
              ↓
   correct / incorrect + answer
              ↓
          Next word
```

This keeps the satisfying Quizlet rhythm—large card, one prompt, quick reveal,
clear progress—without the extra `Again / Almost / Know it` decision.

## Screen-by-screen setup

### 01 — Vocabulary home

- Large `Vocabulary` title and one hero: **Today’s words**.
- Hero shows one scene image, the number of words, and an estimate.
- One primary action: **Start flashcards**.
- One quiet status row: `184 words learned · 12 to review`.
- One secondary link: **All word sets**.

No dashboard, no multiple recommendation cards, no learning-mode grid.

### 02 — Word sets

- A simple Apple-style list of sets, not a two-column card grid.
- Each row has a title, level, word count, and one status value.
- `Today’s words` stays first and visually prominent.
- `Create a set` is a single quiet row, not a new decision tree.

### 03 — Flashcard question

- Standard top bar: close, `2 / 5`, and a single overflow/settings control.
- One large image-led card with the English meaning and a human/action scene.
- One prompt: **Choose the French word**.
- Three full-width answer rows. These are the only primary choices.
- One small speaker icon for pronunciation; no hint/translate row by default.

### 04 — Answer feedback

- The selected answer is marked correct or incorrect inline.
- The correct French word, pronunciation, and one short example appear below.
- The answer choices disappear after selection so the state is unambiguous.
- One primary action: **Next word**.
- Wrong words return later in the same set automatically.

### 05 — Create a set

This is an optional sheet reached from `Create a set`, not part of the main
review loop.

- One text field: `What do you want to learn?`
- One optional context line: `travel`, `work`, `morning routine`, etc.
- One button: **Create set**.
- The app prepares the words, images, examples, and audio before showing the
  set. If generation fails, it offers existing curated words.

### 06 — Complete

- `5 words completed` and a plain result such as `3 correct · 2 to review`.
- Show only the words that need another pass.
- One primary action: **Review mistakes**.
- One secondary action: **Done**.

## Image system

Images are memory cues tied to meaning, not decorative backgrounds.

1. Search an approved public/curated source first, using the word, action, and
   setting. Store the source URL and license metadata.
2. Prefer a clear human action or object: `bonjour` → someone waking and
   greeting a person; `attendre` → someone waiting at a bus stop.
3. If no useful image exists, generate a fast, deterministic fallback with a
   single subject, one action, no text, no logos, no flags, and no surreal
   details.
4. Crop every result to the same card frame and cache it by concept + context.

The wireframe uses a real project image as a stand-in so the image behavior is
visible. Production can swap the image resolver without changing the UI.

## Vocabulary content packet

Before a set is shown, freeze:

- French word and English meaning;
- part of speech and CEFR level;
- image plus provenance;
- pronunciation and stable audio key;
- one short example sentence;
- accepted answer and three distractors;
- review state and source set.

Distractors should be plausible but unambiguous. The first version can use
three-choice recall only. Typed recall can be added later without changing the
home or set architecture.

## Automatic repetition logic

- Build sets from due words first, then mission words, then new words.
- Use small fixed sizes: Quick 3, Standard 5, Deep 8.
- Correct answers schedule the next review farther away.
- Incorrect answers schedule a near-term retry and reinsert the word before the
  set ends when appropriate.
- Pause saves the exact set, card, and answer state.
- There is no hidden “good” grade and no self-reported mastery.

## Apple-style rules applied

- One primary action per screen.
- Standard top navigation with a clear back/close affordance.
- Lists and disclosure rows for secondary choices instead of decorative card
  islands.
- Inline feedback for normal answer states; sheets only for scoped tasks such
  as creating a set.
- Controls target at least 44pt and have generous spacing.
- Reduce Motion turns the card flip into an immediate state change.
- Keep the global tab bar on home/list screens and remove it during the focused
  flashcard session.

## Deliberately removed

- self-grading buttons;
- Speaking, Listening, Reading, Writing, and Grammar from Vocabulary;
- visible six-stage lesson rails;
- floating tutor/notetaker controls;
- mode-selection grids;
- decorative progress islands and repeated status cards;
- swipe-only progression.

