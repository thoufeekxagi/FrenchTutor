# Vocabulary V5 — five-set maker

Status: design proposal only. No application code is changed.

This is the next pass after the pure-flashcard rebuild. Vocabulary stays
strictly vocabulary; the only choice is which word set to open and how much
content to show on each flashcard.

## Product shape

The Vocabulary home has five simple set choices, matching the predictable
catalog structure used by Speaking and Writing, while avoiding a wall of
decorative cards:

1. **Today’s words** — automatic due + new set, always first.
2. **Course words** — vocabulary attached to the learner’s current course.
3. **Recent practice** — words surfaced from recent sessions and mistakes.
4. **Everyday topics** — curated topic sets such as café, travel, and home.
5. **Create a set** — learner topic or automatic generation with Marie.

The first set is featured with the only dominant `Start flashcards` action.
The remaining four are plain list rows. Five choices are available without
creating five competing visual islands.

## Two study options

This is not a mode picker. Both options are still flashcards:

- **Words only** — image, French word, pronunciation, and English meaning.
- **Words + sentences** — the same card plus one short example sentence after
  the answer is checked.

The selection is a small two-option control and persists for the next session.
We can tune the ratio later; the wireframe supports both without changing the
set architecture.

## Flashcard behavior

The card asks an objective question. The learner chooses one of three French
answers. The app immediately knows whether it is correct, shows the answer,
and advances with one `Next word` button. There is no self-grader, no silent
mastery, and no swipe-only interaction.

For `Words only`, feedback is deliberately short. For `Words + sentences`,
the answer state adds the single sentence tied to that word. The image remains
visible in both cases.

## Automatic set generation

`Today’s words` is assembled locally from due vocabulary first, then current
course words and a small number of new words. When the next automatic set is
needed, the app prepares it in the background so opening Vocabulary is fast.

`Create a set` can accept a short topic such as `morning routine`. The set
builder prepares the word list, distractors, image, pronunciation, example,
and audio before the set becomes visible. Existing curated content is the
fallback when generation or image lookup is unavailable.

## Image injection

For each concept, query an approved public/curated source first. Prefer a
single clear human action or object: `bonjour` can show someone waking and
greeting another person; `attendre` can show a person waiting at a bus stop.
If no useful image is found, generate a simple, cached image with no text,
logos, flags, surreal details, or irrelevant props. Store source/license data
or the generation prompt with the word packet.

## Screen list

1. Vocabulary home with the automatic featured set, the two study options, and
   five set choices.
2. Set preview with word count, image, and a short word list.
3. Flashcard question with one image cue and three objective answers.
4. Automatic answer feedback with optional sentence depth.
5. Create-a-set sheet with one topic field and one action.
6. Completion with correct count, words to review, and one next action.

## Rules for the eventual build

- Vocabulary does not open Speaking, Listening, Reading, Writing, Grammar, or
  tutor-call screens.
- Global navigation remains on home/list screens and disappears in the active
  flashcard session.
- Use a standard back/close affordance and one primary action per screen.
- Use list rows and a scoped sheet for secondary actions.
- Keep controls at least 44pt with enough spacing between them.
- Feedback is inline; alerts are reserved for real problems or destructive
  actions.
- Pause persists the exact set and card.

