# Speaking — current implementation contract

Status: source-of-truth for the standalone Speaking rebuild.

This file supersedes older Speaking Studio and generic live-call descriptions.
The app dashboard remains independent. This contract starts only when the
learner opens Practice → Speaking (or a Speaking course item).

## Product boundary

Speaking is its own product surface. A Speaking card must never open
Vocabulary, Grammar, Writing, Reading, or the mixed-skill dashboard.

The only current Speaking modes are:

1. Guided — one useful French line at a time.
2. Free talk — a structured open prompt with a visible French starter.
3. Roleplay — the preserved actor-coach scene with Marie and the learner.

Immersive roleplay, the generic full-screen tutor portrait, and the old
Vocabulary/Verbs quick-lessons route are not part of this surface.

## Entry flow

```text
App dashboard (unchanged)
  → Practice tab
    → Speaking
      → SpeakingCourseHomeScreen
        → mode picker: Guided | Free talk | Roleplay
        → beginner lesson/card
          → dedicated player
```

Course items use the same dedicated player path:

```text
Course speaking item
  → SpeakCourseActivityScreen / SpeakCourseSessionScreen
    → Guided player, Free-talk player, or Roleplay setup
      → completion result
        → course progress + durable completion key
```

## Speaking home

`SpeakingCourseHomeScreen` owns the screen opened by Practice → Speaking.
It displays:

- current learner band, clamped to A1/A2 for the beginner bank;
- three mode controls;
- one featured beginner lesson with Hear → Say → Check phases;
- dedicated speaking lesson cards;
- square speaking collection cards;
- completion marks from the speaking content key.

The beginner bank is permanent and local. It does not depend on an adaptive
course row existing, so a fresh learner cannot see “No Unit 1 speaking lessons
are available yet.” It contains 30 authored speaking lessons across A1 and A2,
including introductions, greetings, help, cafés, directions, trains, shops,
and plans with friends.

Adaptive course generation may add future course items, but it does not replace
or hide this bank.

## Guided player

`SpeakingLessonFlowScreen` is one continuous route:

1. Show one French phrase large and central.
2. Show the English meaning and a short level-appropriate tip.
3. Play the model line at a deliberately slow beginner pace.
4. The learner holds/taps the microphone and records one attempt.
5. The transcript is displayed as “I heard.”
6. The client checks the spoken words against the target line.
7. A match becomes green and enables the next phrase.
8. A miss remains on the same phrase with a retry instruction.
9. Empty transcription is an explicit error; it never counts as success.
10. The last successful phrase returns a `SpeakingResult`, then the content key
    is marked complete by the speaking home/course parent.

No result page or generic AI-call fallback is inserted between phrases.

## Roleplay player

The roleplay engine remains `AgentLedListeningScreen`, because it already has
the correct legacy behavior:

- Marie speaks the character line first;
- Marie coaches in English and teaches the learner’s reply;
- the scene grows as a two-sided transcript;
- character lines are left bubbles and learner lines are right bubbles;
- every line has a speaker button for replay;
- Back, Next sentence, and End remain explicit controls;
- the app owns the scripted beat order rather than letting a model navigate it.

The current upgrade adds visible verification without replacing that engine:

- the current learner target remains visible;
- the user transcript is stored against the current beat;
- a close match displays a green `Matched` strip and green learner bubble;
- a miss displays an amber `Try again` strip on the same beat;
- the next beat remains a button-controlled transition;
- roleplay uses the dark/gold Speaking skin and hides the unrelated floating
  notetaker overlay.

The roleplay setup shows goal, learner/tutor roles, phrasebook, and one
`Start roleplay` action. There is no Chat/Immersive switch and no alternate
generic call screen.

## Free talk

Free talk uses the same controlled player surface, but each line is marked as
an open response. The learner receives a prompt and a French starter such as
`Aujourd’hui, ça va…`, then records at least a short response. The transcript
is shown and the learner advances only after a non-empty response is heard.
This keeps Free talk independent while avoiding an unbounded generic tutor
call during the beginner experience.

## Level contract

| Band | Content rule |
| --- | --- |
| A1 | Greetings, identity, concrete needs, short present-tense phrases, one idea at a time. |
| A2 | Everyday past/future references, simple reasons, choices, and short connected exchanges. |
| B1 | Reserved for the next authored expansion: opinions, explanations, connected discourse. |
| B2 | Reserved for the next authored expansion: nuance, register, complex reformulation. |

No generated or adaptive item may silently replace a pinned lesson level.

## Verification checklist

- [x] App dashboard is not changed by the Speaking route.
- [x] Practice → Speaking opens the independent Speaking home.
- [x] Speaking home always has beginner lessons.
- [x] Speaking cards do not navigate to Vocabulary or Grammar.
- [x] Guided mode has phrase → record → transcript → green/retry states.
- [x] Roleplay preserves the legacy Marie + learner transcript engine.
- [x] Roleplay adds per-beat green/try-again verification.
- [x] Immersive roleplay and generic tutor portrait flow are not reachable from the new Speaking home.
- [x] Course speaking/free-talk/roleplay items use dedicated routes.
- [ ] Phone visual/audio QA remains to be run by the developer; no Flutter build or simulator was run during this source-only pass.
