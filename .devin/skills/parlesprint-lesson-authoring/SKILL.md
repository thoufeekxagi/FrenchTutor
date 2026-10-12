---
name: parlesprint-lesson-authoring
description: Author deterministic TCF Canada lessons (Stage 0 sounds, A1 to B2 units) as files under content/tcf/, validate them, and prepare the Gemini Live audio bake list. Use for any syllabus, unit, lesson, vocabulary, grammar, dialogue or TCF-corner work.
triggers:
  - user
  - model
allowed-tools:
  - read
  - grep
  - glob
  - exec
  - edit
  - write
---

# ParleSprint lesson authoring

Read `docs/v3/CONTENT_AUTHORING.md` first. You write the lessons yourself as
files. No GPT/OpenRouter generation, no TTS.

## Per unit, in order

1. Read the unit's syllabus entry and the previous unit's word list.
2. Read the artifact validators in
   `supabase/functions/prepare-course-lesson/index.ts` so field names and
   limits match what the renderers accept. Never guess a schema.
3. Write `content/tcf/units/<stage>/<unit-id>/unit.json` (six lessons, fixed
   order) and `audio.json` (every French string to bake, with voice).
4. `python3 content/tcf/tools/validate.py`. Fix until green.
5. Blind audit: re-solve every question from the file only, compare to keys.
6. Commit the unit alone.

## Content rules

- Beginner-first English explanation, one idea per card.
- Cumulative vocabulary only. Canadian situations. Clear standard French for
  production, Canada vs France differences marked.
- Original text. Sources set targets and patterns, never copied wording.
- TCF corner items match the real format (one-play listening, 4 options,
  scales and task word counts in CONTENT_AUTHORING.md). Never promise scores.
- Marie is a voice and helper. She never changes the curriculum.
- A fluent speaker must review pronunciation claims and baked audio. You
  cannot judge audio; say so in the unit's `review.json`.
