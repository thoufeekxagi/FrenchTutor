# Vocabulary V3 — minimal workout and flashcard-first approach

Status: new proposal only. This is a fresh direction and does not extend the
legacy vocabulary screens. No application code is changed.

## The core idea

Vocabulary has one job: help the learner remember a useful word and use it
again later. The product surface should therefore feel like a daily workout,
not a dashboard full of decks, stages, badges, and controls.

The learner sees one large review invitation, chooses one way to practise, and
enters a focused session. Everything else is secondary and can live behind a
small “Your vocabulary” link.

## The new flow

```text
Vocabulary home
        ↓ Review now
How would you like to review?
        ↓ one mode
Set preview
        ↓ Start
Focused practice loop
        ↓ finish or review misses
Simple result
```

The former six-stage `Preview / Learn / Recall / Context / Use / Done` model is
an internal content recipe, not a visible navigation system. The learner gets
one progress line such as `2 / 8`, one prompt, and one next action.

## Screen-by-screen contract

### 01 — Vocabulary home

- Lead with **Daily vocab workout** and one primary action: **Review now**.
- The hero can show one memorable scene image, the due count, and a time
  estimate.
- Keep only a quiet status line below: `184 words learned · 12 to revisit`.
- Do not show every collection, phase, or recommendation on the first view.
- “Your vocabulary” opens the later word-status view.

### 02 — Review mode selection

Show four simple rows, using the same set and the same word status:

- **Speaking** — see the scene and say the word or a short sentence.
- **Flashcards** — Quizlet-style reveal and self-grade.
- **Writing** — complete or write one useful sentence.
- **Reading** — meet the word inside a short passage.

Each row gets one icon, one sentence, and a small item count. No grid of
feature cards and no second decision about difficulty on this screen.

### 03 — Set preview

- Show the set title, one image, level, word count, and a small status summary.
- Show a short list of words with `New`, `Building`, or `Ready` labels.
- Use one dominant **Start** button. Mode switching is a quiet text action.

### 04 — Flashcard front

This is the default practice mode and the visual center of the redesign.

- Top bar: close, `2 / 8`, and settings. No stage labels.
- One large card with a human/action image and a simple prompt.
- Maximum three helper controls: **Listen**, **Hint**, **Translate**.
- Primary action is **Tap to reveal**. A swipe can be a convenience, never the
  only way to advance.

### 05 — Flashcard revealed

- Keep the image visible so the memory cue survives the flip.
- Reveal French, pronunciation, English meaning, and one short example.
- The speaker icon sits next to the French word.
- Replace the reveal action with exactly three self-grade choices:
  **Still learning**, **Almost**, **Know it**.
- Each choice shows the next review window in small text.

### 06 — Result

- Say what happened: `6 of 8 ready`, `2 to revisit`.
- List only the words that need action.
- Primary action: **Review misses**. Secondary action: **Done**.
- The learner can leave with confidence; no confetti, streak pressure, or
  invented proficiency score.

## Image system

Images are a memory aid, not decoration. Every image request is tied to the
meaning and the situation of the word.

1. Search a licensed public/curated source first (for example Unsplash or an
   internal approved image library) using the word, action, setting, and level.
2. Prefer one clear human action or object: `bonjour` → a person waking and
   greeting someone; `attendre` → a person waiting at a bus stop.
3. If no good result exists, generate a compact editorial illustration/photo
   with a deterministic prompt. No text inside the image, no strange hands,
   flags, logos, or irrelevant visual metaphors.
4. Crop to a consistent 4:3 card frame, store the source/license or generation
   prompt, and cache by concept + context so the same word stays visually
   stable across sessions.

The wireframe uses a real project image as a stand-in so the image-led behavior
is visible. Production can swap the resolver without changing the card layout.

## Content model

Create one immutable vocabulary item packet before the session starts:

- word, translation, part of speech, CEFR level;
- primary image and provenance;
- pronunciation and stable audio key;
- one anchor sentence;
- two to six alternate contexts across speaking, listening, reading, and
  writing;
- source links to the current mission, recent sessions, and learner mistakes.

The same word may return, but each return must have a different learning job.
Do not repeat the same isolated flashcard seven times.

## Queue and repetition logic

- Build the workout from due reviews first, then mission words, then recent
  cross-skill misses, then optional new words.
- Default sizes stay humane: Quick 3–4, Standard 5–6, Deep 8–10 total items.
- A miss can return in the same workout; it does not force a restart.
- `Still learning`, `Almost`, and `Know it` map to the scheduler while keeping
  the learner-facing language human.
- Save the exact word and mode on pause so reopening continues where the learner
  stopped.

## What is deliberately removed

- No visible six-step lesson rail.
- No multiple horizontal carousels on the home screen.
- No floating notetaker on every surface.
- No simultaneous “choose a category + choose a mode + choose a session
  length” decision stack.
- No silent grade or forced swipe gesture.

## Later, not in this first implementation

The detailed word-status view can later expose `New / Building / Ready`, review
history, and source context. The first release only needs the compact status
line and result summary to make progress legible without creating another
dashboard.

## Reference patterns

The direction is informed by Babbel’s “Daily vocab workout” and mode chooser,
Babbel’s image-led lesson cards, and Quizlet’s set preview, large flashcard,
reveal, and completion sequence. The product should borrow the clarity of those
flows while keeping ParleSprint’s charcoal/gold visual identity.

