# V3 Speaking Redesign — Speaking Studio Wireframes

## Proposal status

This is a new speaking wireframe proposal. It replaces the earlier one-phone
“Practice Loop” presentation because that version reduced the product to a
recorder. This proposal treats speaking as a connected scene with a clear
beginning, middle, coaching moment, and next step. No Flutter UI code changes
were included when this proposal was drafted.

## Implementation status

- **Screen 1 — Speaking Studio / Your next conversation:** implemented in
  `lib/screens/speak/speaking_studio_screen.dart` and now used as the primary
  Home surface from `main_tab_screen.dart`. It gives the next scene a dominant
  hero, keeps Warm up / Free talk / Review as compact quick starts, shows real
  roadmap progress, and includes a scrollable Continue / Speaking / Writing /
  Reading / Listening rail.
- **Global Home:** now intentionally uses Speaking Studio as its primary
  surface. The previous `lib/screens/speak/speak_home_screen.dart` remains in
  the repository as the preserved Home implementation for safe rollback, but
  it is not a runtime fallback.
- **Guided Speaking entry:** implemented in
  `lib/screens/speak/speaking_practice_screen.dart`. Home's Speaking rail and
  Practice → Speaking both open this screen, which hands off to the existing
  Scene Brief and live tutor engine.
- **Screen 2 — Scene Brief / Before you speak:** implemented in
  `lib/screens/speak/speak_course_activity_screen.dart` for speaking,
  roleplay, and free-talk course entries. The learner now sees the scene,
  roles, goal, opening line, and an explicit “enter the scene” action before
  the existing tutor engine starts.
- **Screens 3–5 — Live Scene, Turn Coach, Scene Complete:** remain the next
  screen-level implementation steps. The underlying live tutor/session engine
  is preserved for those screens.

## Product thesis

Speaking should feel like entering a tiny French scene, not opening a form.
The learner should always know:

1. where they are;
2. what their role is;
3. what the conversation is trying to achieve;
4. whose turn it is; and
5. what to do after the app hears them.

The new system is called **Speaking Studio**:

    Choose a scene → get a role and goal → speak in a bubble exchange
                 → get one useful coach note → keep the scene moving

The unique Marcus layer is the **move-based conversation**. Every scene has
one practical objective, such as asking for a recommendation or checking out
at a hotel. A learner earns a move by completing that objective, not by
surviving an abstract score screen.

## Research and evidence

### Speak

Mobbin’s Speak references show a useful progression: a short prompt and
progress counter, a character-led scene with the phrase visible, a large
microphone action, and a type fallback. The strongest references are the
[guided warm-up](https://mobbin.com/screens/3e01c79e-3175-4df8-9fc6-91966389ffb3),
[immersive character scene](https://mobbin.com/screens/c4158d13-ba1a-4968-b164-c07777329a7e),
[recorded response / retry state](https://mobbin.com/screens/de1bc541-ca8d-4e50-9fda-cea0c3ca009f),
and [typing fallback](https://mobbin.com/screens/78491d94-dcb5-4a8c-9d19-c03560166bef).

Speak’s own description frames the product as useful phrases first, practice
until they become natural, then real back-and-forth conversation:
[Speak Method](https://www.speak.com/?lang=en).

### Busuu and Babbel

Busuu’s speaking practice keeps the native model, the target phrase, the
recording action, and personalized pronunciation feedback in the same lesson.
Its Conversations feature adds realistic scenario practice after that
rehearsal. See [Busuu speaking practice](https://blog.busuu.com/speaking-practice-release/),
[Busuu Conversations](https://help.busuu.com/hc/en-gb/articles/21862192336402-What-are-Busuu-Conversations-and-how-can-they-help-me-speak-a-language),
and the [Babbel listen-and-repeat reference](https://mobbin.com/screens/66a71748-3aff-45a7-bcaf-5ff35a080ad1).

### Bubblz / “Bubble”

The closest verifiable match to “Bubble” is [Bubblz](https://play.google.com/store/apps/details?hl=en-US&id=com.bubblz).
Its public product description uses the exact interaction we need to borrow:
pick a scenario, speak or type with an AI partner, and receive corrections and
more natural phrasing while the conversation continues. The wireframe below
uses that message-bubble behavior, but keeps Marcus’s learning objective and
progress visible.

### Jusu

The exact name “Jusu” did not produce a reliable language-learning product in
public search, and a Mobbin search returned Speak and unrelated conversational
apps. It is therefore not used as evidence in this proposal. If the intended
app has a different spelling or a private link, it can be added as a reference
without changing the interaction model below.

## Inventory of the existing speaking screens

| Existing screen | What it currently does | Decision in Speaking Studio |
|---|---|---|
| `SpeakHomeScreen` | Shows next action, roadmap, “Call tutor,” recent activity, and profile access. | Keep as the entry point; make one scene the obvious next action. |
| `SpeakCourseActivityScreen` | Routes a selected activity and shows “Opening your speaking practice…” while preparing it. | Keep as routing only; never expose the spinner as a learner-facing destination. |
| `SpeakCourseSessionScreen` | Shows a course activity, time, lesson contents, and start/finish actions. | Merge the useful context into Scene Brief; remove duplicate start screens. |
| `SpeakLessonScreen` | Presents a topic, one speaking target, a model phrase, and why the tutor will help. | Keep the target phrase and model audio; move them into Scene Brief. |
| `SpeakFreeTalkScreen` | Offers topics such as café, directions, reservation, and meeting someone. | Keep the scenario chooser; make each topic open Scene Brief, not a dead-end card. |
| `SpeakRoleplayScreen` | Presents the scene, learner role, tutor role, goal, opening line, and useful phrases. | Keep the role/goal/opening-line content; combine it with the guided lesson. |
| `SessionScreen` | Runs the live tutor call with status, transcript strip, tutor stage, mic controls, report, and end call. | Re-skin as the Live Scene: bubbles first, stable tutor presence, clear turn state. |
| `SpeakTutorPrototypeScreen` | QA/prototype view of tutor portrait, transcript, hear tutor, and typed line. | Keep as a test reference only; fold its best ideas into Live Scene. |
| `SpeakReviewScreen` | Chooses how to review recent speaking practice and starts review generation. | Keep outside the scene; open it from Recap or Practice. |
| `SpeakCourseVocabularyScreen` | Reviews words from a session with retry and finish. | Use as a follow-up path from Recap, not as a second speaking result screen. |
| `SpeakChallengeScreen` | Shows time, conversation, and streak challenges. | Keep as motivation content on Home; do not interrupt the scene. |
| `StreakCalendarScreen` | Shows recent activity and streak history. | Keep in progress/profile; no change to the live flow. |
| `FrenchFingerprintScreen` | Shows practice signals and the learner’s French profile. | Keep as progress/profile; use its signals to choose the next scene. |
| `SpeakProfileScreen` | Shows learner profile and speaking-related navigation. | Keep as account/progress shell. |
| `SpeakSettingsScreen` | Controls learning language, tutor voice, and account controls. | Keep in the persistent top-right settings action. |
| `SpeakAdvancedSettingsScreen` | Controls skills and reminders. | Keep as preferences; do not put these controls inside a scene. |
| `MocksScreen` | Runs a speaking mock with timed tasks and post-mock feedback. | Keep as an exam mode with its own contract; do not force it into the casual scene flow. |
| `ExamReadinessScreen` / `ExamPracticeScreen` | Handles exam preparation and timed exam activities. | Keep separate from everyday speaking. |
| `speak_ui.dart` | Shared scaffold, header, cards, buttons, and common speaking styling. | Reuse the component layer; replace card-heavy composition with scene and bubble primitives. |

## What is being simplified

- **Lesson + Roleplay become one Scene Brief.** The learner should not read one
  page and then read the same setup again before the conversation.
- **Home gets one dominant next action.** Topic cards still exist, but the
  product tells the learner what to do next instead of presenting a dashboard
  of equally important cards.
- **The live screen stops being a blank tutor call.** The scene, turn, prompt,
  and learner response stay visible as an exchange.
- **Feedback stays attached to the learner’s latest bubble.** The learner can
  retry the exact line or keep going without losing the conversation context.
- **Result becomes a next move.** Finish should return the learner to a useful
  action: replay one tricky phrase, review the earned phrases, or start the
  next scene.

## New screen set

The interactive preview contains these five editable states:

### 1. Home — “Your next conversation”

Purpose: get the learner into a meaningful scene in one tap.

    ┌──────────────────────────────────────┐
    │ ‹  Marcus Speak                 ⚙  ⋯ │
    │                                      │
    │  GOOD MORNING, MARCUS                 │
    │  Your next conversation               │
    │  ┌────────────────────────────────┐  │
    │  │  [scene image / warm gradient] │  │
    │  │  NEXT UP · 3 MINUTES            │  │
    │  │  Order at the café              │  │
    │  │  Ask for a recommendation       │  │
    │  │                 Continue  →     │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  QUICK START                         │
    │  Warm up  ·  Free talk  ·  Review    │
    │                                      │
    │  TODAY                                │
    │  4 min spoken · 2 moves completed     │
    └──────────────────────────────────────┘

Rules:

- Keep settings and More in the same top bar as Reading and Listening.
- Do not make five large format cards compete for the first tap.
- A scenario card must show topic, goal, level, and approximate duration.

### 2. Scene Brief — “Before you speak”

Purpose: remove anxiety and explain the social situation before the mic opens.

    ┌──────────────────────────────────────┐
    │ ‹  At the café · A1             ⚙  ⋯ │
    │                                      │
    │  SCENE 1 OF 3                         │
    │  ┌────────────────────────────────┐  │
    │  │  [illustrated café scene]      │  │
    │  │  You are the customer          │  │
    │  │  Marcus is the server          │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  YOUR MOVE                           │
    │  Ask what the server recommends.     │
    │                                      │
    │  Marcus says                         │
    │  ┌────────────────────────────────┐  │
    │  │ Vous cherchez quelque chose ?  │  │
    │  │                        🔊 Hear │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  USEFUL PHRASE                       │
    │  Qu'est-ce que vous recommandez ?    │
    │  “What do you recommend?”             │
    │                                      │
    │  [  I'm ready — enter the scene  ]   │
    └──────────────────────────────────────┘

Rules:

- The learner sees the social goal before the French sentence.
- French remains visually primary; English is a small support line.
- “Hear” is next to the tutor bubble, not hidden in a global audio control.

### 3. Live Scene — “Your turn”

Purpose: make speaking feel like a natural exchange while keeping learning
support one tap away.

    ┌──────────────────────────────────────┐
    │ ×  At the café   MOVE 1/3       ⋯    │
    │  ━━━━━━━━━━━━━━━○━━━━━━━━━━━━━━       │
    │                                      │
    │  MARCUS · SERVER                      │
    │  ┌────────────────────────────────┐  │
    │  │ Vous cherchez quelque chose ?  │  │
    │  │ “Are you looking for something?”│  │
    │  │                         ▶ Hear │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  YOUR TURN                           │
    │  Ask what he recommends.              │
    │  ┌────────────────────────────────┐  │
    │  │ Qu'est-ce que vous             │  │
    │  │ recommandez ?                  │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  [ Hint ] [ Slower ] [ Type instead ]│
    │                                      │
    │             ◉  Hold to speak        │
    │       Listening · release to send   │
    └──────────────────────────────────────┘

Rules:

- The tutor’s line and the learner’s objective are separated into bubbles.
- `YOUR TURN` is the strongest state cue; it should never be inferred from a
  generic “Listening” label.
- The mic is a large press-and-hold action; “Type instead” is always available.
- Hint, Slower, and Type are supporting actions, never four competing primary
  buttons.
- The stable tutor/avatar visual can live behind or beside the bubble stack;
  it must not push the actual words off-screen.

### 4. Turn Coach — “Make this line stronger”

Purpose: turn recognition into a useful correction without stopping the scene.

    ┌──────────────────────────────────────┐
    │ ×  At the café   MOVE 1/3       ⋯    │
    │  ━━━━━━━━━━━━━━━○━━━━━━━━━━━━━━       │
    │                                      │
    │  YOU                                 │
    │  ┌────────────────────────────────┐  │
    │  │ Qu'est-ce que vous             │  │
    │  │ recommandez ?                  │  │
    │  │  00:03 · replay                │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  COACH NOTE                          │
    │  Clear and polite. Try the final     │
    │  “dez” a little more lightly.        │
    │                                      │
    │  NATURAL VERSION                     │
    │  Qu'est-ce que vous recommandez ?    │
    │  ────────●────────                  │
    │  clear     almost     try again      │
    │                                      │
    │  [  Try this line again  ]           │
    │  [  Keep going →        ]            │
    └──────────────────────────────────────┘

Rules:

- Preserve the learner’s actual transcript and mark the one word or sound to
  work on. Do not replace it with a mysterious score.
- Coach feedback is one sentence plus one playable model.
- “Keep going” is the positive default when the learner is understood.
- Retrying returns to the same Move, not to the Home screen.

### 5. Scene Complete — “You made the move”

Purpose: give a satisfying finish and a clear reason to come back.

    ┌──────────────────────────────────────┐
    │ ‹  Scene complete                ⋯   │
    │                                      │
    │  YOU MADE THE MOVE                   │
    │  You handled a café recommendation.  │
    │                                      │
    │  CONVERSATION RECAP                  │
    │  ✓ ask politely                       │
    │  ✓ understand the answer              │
    │  ○ pay and say thank you              │
    │                                      │
    │  KEEP THESE                           │
    │  [ Qu'est-ce que… ] [ Je prends… ]   │
    │  [ C'est combien ? ]                  │
    │                                      │
    │  NEXT BEST STEP                       │
    │  Finish the order in 90 seconds.      │
    │  [ Replay one line ]  [ Next scene ]  │
    └──────────────────────────────────────┘

Rules:

- Celebrate the completed social action, not an arbitrary percentage.
- Show the phrases the learner actually used or nearly used.
- Offer one next scene that continues the same context and one replay path.
- Save a compact recap to Review and Recent Activity.

## Component map

Reuse the existing `speak_ui.dart` primitives where they help with spacing,
buttons, and accessibility, then add these product primitives at the shell
level:

- `SpeakingHeader`: back/close, scene title, progress, settings, More.
- `SceneHero`: topic art, roles, level, and duration.
- `MoveProgress`: scene count and current objective.
- `TutorBubble` / `LearnerBubble`: text, translation, audio, timestamp, and
  feedback marker.
- `TurnDock`: hold-to-speak, type fallback, hint, and slower controls.
- `CoachCard`: actual transcript, one correction, replay, retry, continue.
- `SceneRecap`: earned moves, useful phrases, and next best step.

`SessionScreen` remains the runtime conversation engine. The proposal changes
the information hierarchy around it: the conversation is the main content,
while microphone status and transport controls are supporting controls.

## Interaction contract

| Event | Result |
|---|---|
| Tap a Home scene | Open Scene Brief with the selected topic and level. |
| Tap Hear | Play the tutor line and show a short “Marcus is speaking” state. |
| Tap I’m ready | Open Live Scene with Move 1 active. |
| Hold mic | Start recording, show elapsed time and waveform, and label the turn. |
| Release mic | Transcribe and open Turn Coach; preserve the same Move. |
| Tap Type instead | Replace the mic dock with a text entry dock for this Move only. |
| Tap Hint | Reveal the translation or phrase scaffold without leaving Live Scene. |
| Tap Slower | Replay the tutor line at the slower model speed. |
| Tap Try this line again | Return to the same Move with the model phrase ready. |
| Tap Keep going | Save the move and advance to the next tutor response. |
| Finish the final Move | Open Scene Complete and save the recap to Review. |
| Tap More | Open report, transcript, audio, and exit controls without changing the scene. |

## Acceptance checklist for the next design review

- The five screens read as one scene, not five unrelated cards.
- Home has one obvious next action.
- The role and social goal are visible before recording.
- Tutor and learner words use distinct bubbles.
- The mic communicates whose turn it is and whether it is recording.
- The learner can replay, hint, slow down, or type without losing context.
- Feedback identifies a real word or sound and offers an immediate retry.
- The final state gives a next scene and a replay path.
- Reading, Listening, and Speaking keep the same top-right settings / More
  placement.
- This proposal can be edited screen-by-screen before implementation begins.

## Approval gate

Please approve or edit this Speaking Studio wireframe set before any Flutter
screen code is changed.

Waiting for your approval before I edit code.
