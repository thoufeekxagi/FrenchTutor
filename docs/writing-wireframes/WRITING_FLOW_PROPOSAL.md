# Interactive Writing — Proposal

Status: implemented in the current Flutter writing path. The SVGs remain the
approved visual reference; the end-to-end implementation checklist is in
[`WRITING_IMPLEMENTATION_CHECKLIST.md`](./WRITING_IMPLEMENTATION_CHECKLIST.md).

## Product contract

Writing is its own practice system. It must not route into vocabulary, speaking, or the legacy editor by accident.

The learner moves through a controlled ladder:

1. Single-word retrieval.
2. Two- or three-word phrase construction.
3. Full sentence construction.
4. Typed response in a guided dialogue.
5. Independent writing.
6. Inline correction, rewrite, and review.

The course supplies the next saved task immediately. AI generation is used to pre-generate future writing tasks, not as a blocking action when the learner taps a lesson.

## Wireframe files

- [Part 1 — home through typed response](./writing-flow-wireframe.svg)
- [Part 2 — correction through review](./writing-flow-wireframe-part2.svg)

These are visual references for the implemented flow, not screenshots of the
current app.

## Screen map

### 1. Writing home

Purpose: choose the next writing activity quickly.

- Level selector: A1, A2, B1, B2.
- Continue card points to the next saved course writing task.
- Three compact cards: Word, Sentence, Free writing.
- Recent writing reopens saved review state.
- “Create practice” is explicit and secondary.

### 2. Single-word retrieval

Purpose: establish meaning before asking the learner to produce a sentence.

- One context line.
- Two or three answer choices.
- Tap any word for meaning, gender, audio, and example.
- Immediate green success or red correction.
- One primary Next action.

### 3. Phrase and sentence building

Purpose: move from recognition to controlled production.

- The sentence grows in a fixed-width card.
- Word bank stays visible and can be tapped in any order.
- The learner can tap a word for meaning or audio.
- A hint reveals one useful connector, not the whole answer.
- Check validates the built sentence before advancing.

### 4. Typed dialogue

Purpose: introduce real writing without dropping the learner into an empty editor.

- Tutor prompt appears as a dialogue card.
- Learner writes in the same lesson window.
- Suggested words are optional chips, not the answer.
- Helper tools: translate, hint, grammar.
- The keyboard must resize the screen without covering the submit action.

### 5. Inline correction

Purpose: explain the highest-value correction while the learner still remembers the sentence.

- The draft card expands vertically; no new result screen.
- Correct spans use green.
- Unclear or optional improvements use amber.
- Actual errors use red.
- Feedback is grouped by type: accents, agreement, conjugation, word order, preposition, register.
- Show one or two important corrections first; do not flood the learner with an essay.

### 6. Rewrite and retry

Purpose: require retrieval of the correction.

- Show the original sentence and one focused hint.
- The learner rewrites the same sentence.
- Recheck uses the same grading contract.
- Save the corrected phrase for later review.

### 7. Independent writing

Purpose: transfer the skill to meaningful writing.

- Prompt, purpose, audience, register, and target length are visible.
- B1/B2 can use a larger editor and paragraph structure.
- Optional tools remain available but never silently write the answer.
- Submission stays on the same screen until the learner receives feedback.

### 8. Review and continue

Purpose: make the improvement memorable.

- “You wrote” versus “Better version.”
- One next focus.
- Save phrase or correction.
- Continue to the next course task.

## Level ladder

These are internal product targets, not official CEFR word-count requirements.

| Level | Default writing experience | Content guardrail |
|---|---|---|
| A1 | Choose one word, build short phrases, type one simple sentence | familiar nouns, articles, être/avoir/aller, basic places and routines |
| A2 | Build sentences and answer a two- to four-sentence dialogue | past/future basics, connectors, requests, comparisons, everyday plans |
| B1 | Write a message, email, or short opinion | reasons, examples, past events, register, paragraph cohesion |
| B2 | Write a structured argument or formal response | nuance, counterpoint, formal register, complex connectors, precision |

## French correction contract

The evaluator should return structured feedback rather than a single score:

```text
task_id
level_band
submission
accepted: true | false
spans: [{start, end, category, severity, suggestion}]
explanation
improved_version
next_focus
saveable_phrases[]
```

The evaluator must accept valid alternatives. It should not mark a response wrong only because it differs from one canonical sentence.

French-specific categories:

- accents and apostrophes;
- article and gender;
- adjective agreement;
- verb tense and conjugation;
- contractions such as `à + le → au`;
- prepositions;
- word order;
- register and natural phrasing.

Minor punctuation variation should be shown separately from a meaning-changing error.

## Generation and persistence

- Generate the first 50–100 beginner tasks in advance, split across word, phrase, and sentence levels.
- Store each task with level, unit, grammar focus, target vocabulary, acceptable answers, and correction rules.
- When the learner approaches the end of the queue, generate the next batch using current level, course progress, recent errors, and recent vocabulary.
- Save submissions, feedback, rewrites, and review phrases.
- Reopening Recent Writing must show the saved task/review directly, without regeneration.
- If generation or grading is unavailable, show an explicit error state. Do not silently substitute another provider or another activity.

## TEF/TCF mode

TEF/TCF writing should reuse the same editor, keyboard behavior, correction model, and review panel. It changes only the task contract:

- task type;
- audience;
- register;
- time limit;
- target length;
- exam rubric;
- final score breakdown.

It should be a separate card on Writing Home, not mixed into beginner word-building lessons.

## Visual rules

- Dark mode: black, charcoal panels, white type, restrained gold accent.
- Light mode: white, warm gray panels, the same gold accent.
- Keep one primary action per screen.
- Keep feedback inside the active card.
- Avoid large tutor artwork, oversized gradients, and stacked full-width buttons.
- Use a persistent bottom action area similar to the listening player: Hint, Translate, Check/Submit, and Next.

## Reuse from the current code

The existing [`WritingWorkshopScreen`](../../flutter_app/lib/screens/lessons/writing_workshop_screen.dart) already contains the useful stages: brief, build, draft, review, and rewrite. The older [`WritingTaskScreen`](../../flutter_app/lib/screens/lessons/writing_task_screen.dart) and [`WritingLabScreen`](../../flutter_app/lib/screens/labs/writing_lab_screen.dart) should be consolidated behind this flow rather than exposed as competing writing experiences.

## Acceptance checklist

- [ ] Writing Home is independent from Speaking and Vocabulary.
- [ ] A1/A2 start with word and phrase construction.
- [ ] B1/B2 start with guided typed responses and independent writing.
- [ ] Every word can expose meaning and audio without leaving the lesson.
- [ ] Correction expands the same card.
- [ ] Rewrite is required for the primary correction.
- [ ] Multiple valid French answers are accepted.
- [ ] Recent Writing reopens saved state without generation.
- [ ] Course tasks are pre-generated and queued.
- [ ] TEF/TCF uses the same editor and feedback contract.
- [ ] Provider failures are explicit; no silent fallback.
- [ ] Dark and light modes preserve the same hierarchy.
