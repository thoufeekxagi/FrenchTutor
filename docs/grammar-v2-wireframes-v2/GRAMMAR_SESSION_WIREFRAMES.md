# Grammar V2 — session-first wireframes

## The corrected unit

Grammar is session-first, following the existing Speaking lesson contract:

| Mode | Initial sessions | Steps inside each session | Live tutor |
| --- | ---: | ---: | --- |
| Guided | 3 Present sessions | 5 connected beats | Yes, bounded to the current session |
| Complete | 3 Present sessions | 5 connected beats | No |
| Roleplay | 3 Present sessions | 4 connected turns | Yes, bounded to the current scene |

That is 9 home cards and 42 total exercise beats in the first Present reserve.
The beats are nested inside their parent session and are never displayed as
independent library cards. Each session has its own title, topic, grammar
focus, goal, icon, progress, and completion state.

## Session examples

### Guided — 5 beats

`My morning rhythm` → start the day → make a drink → say where he lives →
practise together → arrive at work.

### Complete — 5 beats

`My weekday` → start work → have coffee → eat together → go home → read at
night.

### Roleplay — 4 turns

`Order at the café` → choose a drink → choose a seat → choose payment → close
the exchange.

## Screen contract

1. Home shows the selected tense, the Guided/Complete/Roleplay selector, one
   featured **session**, and a 3-up grid of additional **session** cards.
2. Tapping a session opens one route with `STEP 1 OF 5` or `STEP 1 OF 4`.
3. Next step changes the exercise in place and keeps the same session title and
   grammar objective visible.
4. A wrong answer stays on the current step and offers Try again. A correct
   answer advances. Only the last step can complete the session.
5. Guided and Roleplay show the existing bounded live-tutor action beside the
   lesson heading. Complete stays deterministic and local.
6. The session payload is validated and cached as one SQLite row. Audio is
   warmed for every step when the reserve is saved and again when the session
   opens.
7. Grammar no longer creates or renders visual artwork shelves. Reading and
   Listening retain their own image-card surfaces.

The companion SVG is a visual layout reference for the four independent
states: Home, Guided, Complete, and Roleplay.
