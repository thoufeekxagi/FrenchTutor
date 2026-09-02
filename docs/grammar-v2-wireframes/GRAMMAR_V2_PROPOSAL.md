# Grammar V2 — wireframes and interaction proposal

Status: approved wireframe reference. The learner-facing V2 shell is implemented
in `flutter_app/lib/screens/grammar/grammar_v2_home_screen.dart` and
`flutter_app/lib/screens/grammar/grammar_v2_lesson_screen.dart`.

## Goal

Grammar should feel like Writing: one calm home, a mode selector, a large card
that explains the selected lesson, and a three-column square lesson grid. The
learner practises by choosing language, never by facing an empty editor.

## Screen contract

| Surface | Learner action | Support | Completion |
| --- | --- | --- | --- |
| Home | Filter by tense, select a mode and a lesson | Large explanatory card, level, progress | Opens the selected lesson |
| Guided | Pick the correct form from shuffled chips | English glosses, cached Listen, dynamic Hint, inline tutor call | Check choice, then continue |
| Complete | Choose the missing form from three options | English meaning, grammar note, cached sentence audio | Check answer, then continue |
| Roleplay | Choose a reply/phrase that satisfies the goal | Partner translation, suggestion meanings, hint, cached audio, tutor call | Confirm intent, then continue |
| Tense sheet | Choose Present, Past, Future, Mixed or All | One-line explanation and current count | Returns to the filtered home |

### What is deliberately removed

- No free-typed Grammar answer field.
- No forced rewrite step.
- No unbounded AI conversation inside a Roleplay lesson.
- No separate elongated lesson cards; all library cards are square and three
  across, matching Writing and Speaking.

## Lesson model

Each mode has five authored A1 lessons to start, with the same five-card
reserve per active level and tense filter as the Writing rollout. A lesson is
frozen before it is shown: every French prompt, answer, gloss, hint, audio key,
and accepted choice is stored together.

### Guided

One blank or target form is introduced with a small shuffled word/form bank.
Tapping a chip places it in the answer tray. The tray is flat, left-aligned,
and dynamic. The English gloss is shown beneath the source chip only; the
selected answer remains French-only. `Listen`, `Hint`, and `Translate` share
one row, and the phone helper sits beside the heading.

### Complete

The sentence keeps one `___` blank and offers three options. The correct form
is evaluated against the frozen answer, not against an LLM at tap time. A
compact grammar explanation appears after checking. There is no typing.

### Roleplay

Each beat is a bounded exchange. The partner line and English translation are
fixed, then the learner chooses from three to five prepared replies or word
chips. Intent is checked first; grammar feedback is secondary. The next beat
is selected from the frozen scene, never invented by the live tutor.

## Tense filtering and generation

The home filter is: `Present · Past · Future · Mixed · All`. The active
tense is included in every generation request alongside CEFR level, learner
goal, interests, known vocabulary, and mistake tags. Generated lessons must
return the selected tense explicitly and pass deterministic validation before
being saved. The reserve job keeps at least two incomplete lessons and creates
three candidates when the count drops below that floor.

## Audio and tutor behavior

- Every visible French line receives a stable lesson/step audio key.
- The first line is warmed before opening; remaining lesson lines warm in the
  background.
- `Listen` speaks the exact stored line, never a conversational response.
- A spinner wraps the speaker icon only while a cache miss is resolving.
- The inline phone helper uses the existing simple gold/green + mute behavior.
- Advancing a card silently refreshes the live tutor context.

## Theme and accessibility

Light and dark use the same geometry, spacing, touch targets, and reading
order. Only semantic DesignTokens colors change. Chips remain at least 44pt
high, all icons have VoiceOver labels, Dynamic Type may wrap copy, and Reduce
Motion uses an immediate state change.

## Proposed screens

1. [Grammar home](screens/01-grammar-home.svg)
2. [Tense filter](screens/02-grammar-tense-filter.svg)
3. [Guided grammar](screens/03-grammar-guided.svg)
4. [Complete grammar](screens/04-grammar-complete.svg)
5. [Roleplay grammar](screens/05-grammar-roleplay.svg)

These are implementation wireframes, not final pixel-perfect production
screenshots. The same layout contract is used in light and dark mode.

## Acceptance checklist for approval

- [x] Home and lesson grid feel like Writing/Speaking, including 3-up square
  cards.
- [x] Tense selection is visible, reversible, and reflected in card metadata.
- [x] Guided, Complete, and Roleplay contain no open text editor.
- [x] Every exercise has translation, cached audio, hint, and phone affordances
  without crowding the screen.
- [x] Wrong choices receive a concise explanation and never silently advance.
- [x] Dark mode preserves the same layout and interaction contract.

The initial five-card reserve is frozen and deterministic. Future generated
cards should continue to use the same model validation and exact-audio cache
keys before becoming learner-visible.
