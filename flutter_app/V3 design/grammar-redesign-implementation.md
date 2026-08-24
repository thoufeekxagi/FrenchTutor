# Grammar redesign — implementation contract

## Scope

Grammar is an independent practice surface. It does not route a learner into
Vocabulary, Writing, Speaking, or another lab. Existing generated grammar
stories remain available as saved contextual practice, but they are not used
as a substitute for a curriculum lesson.

## Entry points

All current app entry points continue to open `GrammarLabScreen`:

- Practice → Grammar
- Labs → Grammar
- Home mission or dashboard grammar card
- Speaking course activities tagged as grammar

`GrammarLabScreen` owns existing generation and persistence. Its learner-facing
body is `GrammarCurriculumHomeScreen`.

## Grammar home

1. Show the learner's CEFR level and allow A1, A2, B1, or B2 selection.
2. Show the next incomplete prepared lesson with one primary Start action.
3. Show three compact entry modes:
   - Pick a word
   - Make a sentence
   - Write your own
4. Show same-size lesson cards in a three-column grid. A single tap opens the
   selected prepared lesson immediately.
5. Show Review mistakes after the curriculum grid.
6. Show saved generated grammar stories without regenerating them.
7. Only B1/B2 show an explicit Generate lesson action. Generation never starts
   automatically from opening the screen or tapping a prepared lesson.

## Prepared curriculum

- A1: 30 instant lessons
- A2: 30 instant lessons
- B1: 5 advanced anchor lessons
- B2: 5 advanced anchor lessons

Every lesson is a frozen object with a stable ID, CEFR level, grammar target,
prompt, choices, correct answer, model sentence, English meaning, incorrect
sentence, and advanced-generation grammar point.

## Lesson flow

1. Preview the lesson rule and activities.
2. Pick the correct word or grammatical form.
3. Put a complete French sentence in order. Tapping a tile reveals its meaning.
4. Repair one incorrect sentence.
5. Write one original sentence using the target grammar.
6. Review the score and the first item that still needs repair.

Correct and incorrect feedback expands inside the same exercise card. The card
may grow vertically; its width and surrounding layout do not change.

## Persistence

Prepared lessons use `LearningStore` for in-progress/completed status and score.
An unfinished exercise additionally saves its exact local state:

- current step
- chosen answer
- built sentence tiles
- repair answer
- original writing
- returned writing score and feedback

Generated grammar stories keep using `GeneratedGrammarStoryStore`, including
their frozen explanation, story, quiz, keywords, cover, score, and audio IDs.

## Failure contract

- No content-provider fallback is allowed.
- If original writing cannot be checked, show the error in the writing card and
  do not mark it complete.
- If advanced generation fails, show the generation error and do not create or
  display substitute lesson content.
- Corrupt local resume data may be discarded, but the frozen requested lesson
  itself remains unchanged.

## Verification checklist

- [x] 30 A1, 30 A2, 5 B1, and 5 B2 prepared lessons
- [x] 70 unique stable lesson IDs
- [x] Single-tap lesson card navigation
- [x] Exact unfinished-state resume
- [x] Same-card correct/incorrect feedback
- [x] Explicit B1/B2 generation only
- [x] Existing generated-story persistence preserved
- [x] Adaptive black/gold and white/gold semantic colors
- [x] Targeted Dart analyzer clean
- [ ] Visual phone verification by the user (no simulator/build run)
