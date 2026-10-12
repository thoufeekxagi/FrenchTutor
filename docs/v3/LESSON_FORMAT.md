# V3 lesson format

One lesson is one JSON file. The app plays it; nothing is generated at runtime.

- Lesson files: `flutter_app/assets/content/tcf/lessons/<id>.json`
- Order of the course: `flutter_app/assets/content/tcf/course.json`
  (`{"lessons": ["s0-01.json", ...]}`). The Learn tab offers the first lesson
  that is not finished, then falls back to the legacy adaptive course.
- Dev-only lessons carry `"dev": true` and are hidden in release builds.
- Code: `lib/v3/lesson/` (`v3_lesson.dart` format and parser, `v3_course.dart`
  loader and progress, `v3_lesson_player.dart` the screen).
- Check files with `python3 content/tcf/tools/validate.py`. It applies the same
  rules as the app's parser, so a file that passes will load.

## Lesson

| field | rule |
|---|---|
| `id` | unique, e.g. `s0-01` or `a1-u01-words-a` |
| `title` | shown on Learn and in the lesson |
| `subtitle` | one line, optional |
| `minutes` | estimate shown on Learn |
| `steps` | at least one; step ids unique inside the lesson |

## Step types

| type | shows | fields |
|---|---|---|
| `explain` | plain-English card, optional example lines with speakers | `title`, `body` (paragraphs split by a blank line), `examples[{fr,en}]` |
| `word` | huge French word, speaker, sound guide, meaning, example | `fr`, `en`, `sound`, `exampleFr`, `exampleEn` |
| `phrase` | French phrase, speaker, meaning, tip, "say it out loud" | `fr`, `en`, `tip` |
| `choose` | question, optional French prompt with speaker, answer cards, Check | `prompt`, `promptFr`, `options` (2+, all different), `answer` (index), `explain` |
| `listen` | one-play audio (TCF style), question, answer cards | `fr` (spoken, hidden until answered), `question`, `options`, `answer`, `explain` |

Feedback after Check: green "Correct" or red "Not quite" with the right answer
and the `explain` text. Always write `explain`: it is the teaching moment.

## Voice

Every French string gets a speaker button. It plays Gemini Live in the selected
tutor's voice through the existing `TtsPlayButton`; the clip is made once and
saved. The audio id is `v3-<lessonId>-<stepId>-<slot>`, so changing a lesson's
French text creates new audio automatically. The validator prints how many
French lines a lesson needs voiced.

**Ask Marie** (top right of every step) opens the live tutor with the current
step as context and never reveals an unanswered quiz answer.

## Writing rules

- Plain English first, one idea per card, short sentences.
- A step teaches or tests one thing. A word lesson is 5 `word` steps, then
  `choose` and `listen` steps that reuse those words.
- Only use words already taught (the syllabus word ledger), plus the lesson's
  new words.
- Canadian situations. Mark Canada vs France differences when they matter.
- Original text only.
- TCF questions: four options are fine, three is the minimum the format allows.
