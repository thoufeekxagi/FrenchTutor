# V3 content authoring (how lessons get written, fast and correct)

> **Current method (read `LESSON_PIPELINE.md` first).** Lessons are written in the book
> chapter files and exported; do not hand-write the app JSON as described in the older
> workflow below. Lesson audio is now live tutor speech through the speaker buttons, not
> a baked catalog. The sections below remain correct for sources, the non-negotiables and
> review gates.


The agent (Devin/Claude) writes all lessons directly as files. No GPT or
OpenRouter generation, no TTS. The audience is a true beginner learning for
TCF Canada. Gemini Live (Marie, Julien, Camille, Mathieu) voices every French
string from a baked shared catalog.

## Non-negotiables

1. Deterministic course. Order, words and grammar are fixed in
   `content/tcf/syllabus/`. Nothing is generated per learner.
2. Cumulative vocabulary. A lesson may use only words already taught plus its
   own new words (function words and the tiny always-known set excepted). The
   validator enforces it.
3. Canadian context. Units are Canadian situations (health card, SIN, CRA,
   IRCC, lease, walk-in clinic, winter). Teach clear standard French for
   production. Mark Canada vs France differences explicitly where they matter
   (déjeuner/dîner/souper, courriel, magasiner, fin de semaine). Québec voices
   (Camille, Mathieu) carry the "Hear it in Canada" material.
4. Beginner-first explanation in plain English before any French rule. One
   idea per card.
5. Original text only. Sources define targets and patterns, never copied text.
6. TCF alignment: format, timing and scale from FEI's TCF Canada candidate
   document; NCLC/CLB targets from IRCC and CCLB descriptors; level content
   from the CEFR inventory (EAQUALS, Council of Europe).

## Source use

| Need | Source | How |
|---|---|---|
| Exam format and scales | FEI TCF Canada candidate document and official samples | reference for structure, never copy items |
| Level targets | IRCC and CCLB NCLC/CLB descriptors; CEFR | can-do goals per unit |
| Level content | EAQUALS inventory, Beacco référentiels | grammar and function lists as a spine |
| Word frequency | Lexique 383 (CC BY-SA 4.0, attribute) | word choice and ranking |
| Example patterns | Tatoeba (CC BY 2.0 FR, attribute) | patterns only, rewrite |
| Canadian terms | TERMIUM Plus (Government of Canada open data, verify licence before shipping) | terminology reference |
| Québec usage | OQLF Banque de dépannage, GDT | reference only, datasets are CC BY-NC-SA so never copy into the app |

## Authoring workflow for one unit

1. Read the syllabus entry for the unit and the previous unit's word list.
2. Read the validators in `supabase/functions/prepare-course-lesson/index.ts`
   (`validateVocabulary`, `validateStory`, `validateWriting`, `validateGrammar`,
   `validateSpeaking`) so the file matches what the renderers accept. Do not
   assume field names.
3. Write each lesson as its own file in
   `flutter_app/assets/content/tcf/lessons/` (format: `docs/v3/LESSON_FORMAT.md`)
   and list it in `course.json`. A unit is six lessons in the fixed order:
   words (two 5-word lessons), phrases, grammar mini, dialogue, speak and
   write, TCF corner plus checkpoint. The player and validator already exist.
4. Write `audio.json` next to it listing every French string with its voice
   and lesson id. This is the bake list.
5. Run `python3 content/tcf/tools/validate.py`. Fix until green.
6. Audit pass: re-solve every question blind from the file alone, compare to
   the key. Fix any mismatch.
7. Commit the unit alone (`content(a1-u03): ...`).
8. When a stage is complete: bake audio (see BUILD_STRUCTURE.md), listen to a
   sample, load on the phone, run the on-device test for that stage.

## Pronunciation (Stage 0) rules

- Teach what to hear and say, with minimal pairs (u/ou, dessus/dessous, é/è).
- Notation: plain English approximations for beginners plus the French
  spelling. Use IPA only in a collapsible detail.
- Every sound lesson has Hear, Repeat, Contrast and Check steps, and a
  "Hear it in Canada" clip for the Québec features (affrication of t/d before
  i/u, diphthongised long vowels, relaxed short vowels, fast contractions like
  chu).
- A French speaker must listen to the baked audio before a stage ships.
  The agent cannot judge audio.

## TCF corner rules

- Listening: one play only, 4 options, one correct, distractors plausible and
  based on real beginner errors (numbers, times, prices).
- Reading: signs, notices, short messages at the unit's level.
- Speaking: Task 1 style (directed interview) from A1, Task 2 and 3 later.
- Writing: guided pre-tasks at A1, real tasks (60 to 120 words, 120 to 150,
  120 to 180) from A2/B1.
- Scale reminders for estimates: listening/reading 100 to 699 (A1 100-199,
  A2 200-299, B1 300-399, B2 400-499), writing/speaking 0 to 20. NCLC 7 needs
  roughly 450+ listening and reading and 10+ on writing and speaking.
  Never promise a score.

## Marie and content

Marie never invents or reorders lessons. She gets the current step as context
(the "CURRENT APP STEP" pattern in `lib/prompts/live_prompts.dart`), explains,
models pronunciation, and corrects against the lesson's own targets. The
speaker button plays baked audio, falling back to live generation on a miss.

## Review gates

- Automatic: validator (schema, ledger, keys, duplicates, audio manifest).
- Agent: blind re-solve audit per unit.
- Human: fluent speaker reviews Stage 0 pronunciation and a sample of every
  later stage, and the baked audio. Record who reviewed in the unit's
  `review.json`.


## The book is the source, the app is the product

All A1 content is written by hand once, in `content/tcf/book/chapters/NN_*.py` (plain Python data: words with sound guides, phrases, grammar tables, dialogues, stories, listening, reading, writing, speaking, TCF corner, checkpoint). Two things are made from it:

1. `python3 content/tcf/book/build_book.py` makes the PDF (for the owner to study from and for review).
2. `python3 content/tcf/book/export_app.py` makes the app files: `flutter_app/assets/content/tcf/lessons/*.json`, `stories/*.json`, `course.json`, `stories.json`. **Never edit those generated files by hand.** Fix the chapter file and export again.

Order of work for any change:

```
edit content/tcf/book/chapters/NN_*.py
python3 content/tcf/book/check_book.py      # no word used before it is taught, 4 options, answers valid
python3 content/tcf/book/export_app.py       # also prints any story word that has no meaning
python3 content/tcf/tools/validate.py        # the app's own lesson and story rules
flutter test test/v3_lesson_test.dart test/v3_story_test.dart
tool/e2e_all.sh                              # on the phone
```

What the exporter does and does not do:

- Each WORDS group becomes a word lesson. It adds "what does this mean" and "which word did you hear" checks, built only from the authored list (distractors never share a word with the answer).
- Exercises become multiple-choice only when there are 4 distinct short answers to use as options. Others stay on paper.
- Stories need a meaning for every word. Words that are plain entries in the word tables are filled in automatically. Everything else (verb forms, names, plurals) is hand-written in `content/tcf/book/story_gloss.py`, together with each story's summary and key words.
- Listening and reading questions, explanations, dialogues, grammar tables and notes are carried over unchanged.
