# V3 Speaking Redesign — Speak + Busuu Interaction Contract

> Superseded as the active proposal by [Speaking Studio Wireframes](speaking%20studio%20wireframes.md).
> This file is retained as the earlier research and interaction-contract draft.

## Proposal status

This is the next speaking UI proposal. It documents the screen contract and
interaction states only; no speaking UI code changes are included in this pass.

## Interactive-first decision — 2026-08-20

The unique ParleSprint idea is the **Practice Loop**: each small guided answer
is a satisfying win that unlocks a more natural conversation.

- Ready shows one situation, one goal, one model phrase, and one Record action.
- Recording turns the same action into Stop and makes microphone state visible.
- Feedback returns the actual transcript, one useful correction, and two choices:
  Try again or Continue.
- After a few wins, Continue opens Roleplay with the same tutor, scenario, and
  useful phrases already in context.
- Settings and More stay in the same top-bar position in every state, matching
  the Reading and Listening shells.

The interactive prototype for this contract is intentionally stateful: tapping
the main action moves through recording and feedback, while the state switcher
lets the team review each wireframe state independently.

The product pattern is now:

Reading  → Readle-inspired focused story shell
Listening → Spotify-inspired immersive player
Speaking  → Speak-inspired guided practice + Busuu-inspired feedback

The goal is not to copy either brand. The goal is to make the learner know
exactly what to say, feel safe while recording, and understand what to improve
before moving to the next turn.

## Research findings

### Speak: best reference for the primary speaking lesson

Speak's guided lesson flow is the strongest model for our default speaking
screen:

- A short situation and progress counter establish context before recording.
- The tutor gives one clear prompt, such as “Say, ‘Nice to meet you!’”.
- The learner sees a large, unambiguous recording action.
- The learner can type instead when speaking is not practical.
- After the attempt, the French transcript and a retry path stay in the same
  flow instead of sending the learner to a separate results page.
- Speak's roleplay layer can then expand the guided phrase into a real
  back-and-forth scene.

References: [Speak guided warm-up screen](https://mobbin.com/screens/3e01c79e-3175-4df8-9fc6-91966389ffb3),
[Speak recorded response and retry state](https://mobbin.com/screens/de1bc541-ca8d-4e50-9fda-cea0c3ca009f),
[Speak character conversation screen](https://mobbin.com/screens/c4158d13-ba1a-4968-b164-c07777329a7e),
and the [Speak Q&A lesson flow](https://mobbin.com/flows/eed0e043-6c35-48a6-9a1d-b961328770b7).

Speak's own product description frames the loop as learn a useful phrase,
practice until it becomes automatic, then apply it in real conversation. That
is a good fit for our existing lesson → roleplay architecture:
[Speak Method](https://www.speak.com/?lang=en).

### Busuu: best reference for model-first pronunciation feedback

Busuu contributes the feedback discipline we need:

- Play the native model before asking the learner to speak.
- Keep the target phrase visible while recording.
- Give feedback tied to the recorded speech, not a generic completion state.
- Let the learner repeat the attempt immediately.
- Use realistic conversations after the learner has rehearsed the phrase.

Busuu describes speaking practice as a native pronunciation model followed by
recording and personalized feedback:
[Busuu speaking practice](https://blog.busuu.com/speaking-practice-release/) and
[Busuu support guidance](https://help.busuu.com/hc/en-gb/articles/19367617005970-Mastering-language-skills-through-speaking-practice).
Its newer Conversations feature applies the same idea to realistic AI
scenarios:
[Busuu Conversations](https://help.busuu.com/hc/en-gb/articles/21862192336402-What-are-Busuu-Conversations-and-how-can-they-help-me-speak-a-language).

The useful secondary visual reference is Babbel's listen-and-repeat screen:
[Babbel listen and repeat](https://mobbin.com/screens/c25e73ca-1a5d-4c99-adeb-a7158531a969).

## Recommendation

Use a two-layer speaking experience:

1. **Guided Speaking Drill** — the default, one prompt at a time.
2. **Free Talk / Roleplay** — the richer conversation mode after the learner
   has warmed up.

Guided Drill should be the first screen because it has the lowest friction and
the clearest learning loop:

Hear the model
    ↓
See the target phrase and goal
    ↓
Record one answer
    ↓
Read what the app heard
    ↓
Get one or two useful corrections
    ↓
Try again or continue
    ↓
Apply it in roleplay

The current SessionScreen, Gemini Live service, tutor persona, microphone
controls, transcript strip, recorder, and result view remain the functional
foundation. This proposal changes the visible speaking shell and adds a
small-turn practice state; it does not replace the live tutor backend.

## Screen contract

### Purpose

Help a learner produce one useful French response in a realistic context,
without making them guess what to say or what the microphone is doing.

### Primary action

Record the learner's answer to the visible French prompt.

### Secondary actions

- Hear the native model again.
- Reveal an English hint or a shorter phrase cue.
- Switch to typing when speaking is not practical.
- Cancel or retry the attempt.
- Open Settings and More from the persistent top bar.
- Continue into the next prompt or roleplay.

### States

1. Ready — target phrase and prompt are visible; Record is the dominant action.
2. Model speaking — the app is playing the target; Record is disabled.
3. Recording — waveform, elapsed time, and Stop replace the idle state.
4. Processing — the learner sees that the recording is being transcribed.
5. Feedback — recognized French, correction, and a clear retry/continue choice.
6. Roleplay — the tutor responds naturally and the learner keeps the
   conversation moving.

## Guided Speaking Drill wireframe

    ┌──────────────────────────────────────┐
    │ ‹  Speaking practice          ⚙  ⋯   │
    │                                      │
    │        Meet someone new              │
    │        WARM-UP · QUESTION 1/6        │
    │                                      │
    │  ┌────────────────────────────────┐  │
    │  │  Your goal                     │  │
    │  │  Introduce yourself politely   │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  Tutor                              │
    │  ┌────────────────────────────────┐  │
    │  │ Bonjour ! Je m'appelle Camille.│  │
    │  │                        🔊 Hear │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  Say this in French                  │
    │  “Nice to meet you.”                 │
    │                                      │
    │  ┌────────────────────────────────┐  │
    │  │  Je suis ravi(e) de vous       │  │
    │  │  rencontrer.                   │  │
    │  │  FR target · tap for hint  ▾   │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │              · · ▮▮ · ·              │
    │                                      │
    │          ┌──────────────┐            │
    │          │   🎙 Record  │            │
    │          └──────────────┘            │
    │                                      │
    │       Type instead                    │
    └──────────────────────────────────────┘

### Ready-state rules

- The target phrase is not hidden behind a menu.
- English can be shown as a hint, but the French target remains primary.
- The model audio button sits next to the tutor phrase, not in the bottom
  navigation.
- The recording control is the visual anchor and has a minimum 56pt target.
- The top bar stays stable across every state, like Reading and Listening.

## Recording state

    ┌──────────────────────────────────────┐
    │ ‹  Speaking practice          ⚙  ⋯   │
    │                                      │
    │        Speak now                     │
    │        QUESTION 1/6                  │
    │                                      │
    │  “Je suis ravi(e) de vous           │
    │   rencontrer.”                      │
    │                                      │
    │             00:04                    │
    │        ·▮▮▮▮▮▮▮▮▮·                  │
    │                                      │
    │          ┌──────────────┐            │
    │          │   ■ Stop     │            │
    │          └──────────────┘            │
    │                                      │
    │  Speak naturally. You can try again. │
    └──────────────────────────────────────┘

The recording state must be calm and explicit. Do not animate a character or
show a score while the learner is still speaking. The app should show whether
the microphone is listening, muted, processing, or unavailable.

## Feedback state

    ┌──────────────────────────────────────┐
    │ ‹  Speaking practice          ⚙  ⋯   │
    │                                      │
    │        Nice attempt                  │
    │        QUESTION 1/6                  │
    │                                      │
    │  What we heard                       │
    │  ┌────────────────────────────────┐  │
    │  │ Je suis ravie de vous          │  │
    │  │ rencontrer.                    │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  One useful correction               │
    │  ┌────────────────────────────────┐  │
    │  │ Use ravi for masculine,        │  │
    │  │ ravie for feminine.            │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  Clarity        Good                │
    │  Target phrase  Almost there       │
    │                                      │
    │  ┌────────────────────────────────┐  │
    │  │          Try again              │  │
    │  └────────────────────────────────┘  │
    │  ┌────────────────────────────────┐  │
    │  │          Continue               │  │
    │  └────────────────────────────────┘  │
    └──────────────────────────────────────┘

### Feedback rules

- Show the transcript the recognizer actually heard.
- Keep correction to one or two actionable points.
- Prefer words and phrases over an unexplained numeric score.
- A score is allowed only when the underlying signal is reliable enough to
  explain; otherwise use labels such as Clear, Almost there, or Try again.
- “Continue” should be the primary action when the attempt is usable.
- “Try again” should preserve the same prompt and never reset the whole lesson.

## Roleplay state

After two or three guided prompts, the learner can enter the scenario:

    ┌──────────────────────────────────────┐
    │ ×     At the café              ⚙  ⋯ │
    │                                      │
    │  Camille                              │
    │  ┌────────────────────────────────┐  │
    │  │ Bonjour, qu'est-ce que je      │  │
    │  │ peux vous servir ?             │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  Your turn                          │
    │  ┌────────────────────────────────┐  │
    │  │ Speak in French…               │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  [Hint]                         [🎙] │
    │                                      │
    │  Live transcript appears above the  │
    │  controls as the conversation moves.│
    └──────────────────────────────────────┘

Roleplay should feel like the current tutor call, not like a quiz. The
scenario card, tutor persona, microphone state, transcript, end-session
confirmation, and recap remain familiar. The guided drill is the on-ramp;
roleplay is where fluency and spontaneity are practiced.

## Component map

Reuse:

- SpeakHomeScreen for the Speaking entry point and next-action hierarchy.
- SpeakRoleplayScreen for scenario setup, role, goal, opening line, and useful
  phrases.
- SessionScreen for Gemini Live, tutor persona, lifecycle, audio streaming,
  microphone modes, transcript, recording, session persistence, and recap.
- MicModeBar, MicPrimaryButton, TutorAvatarStage,
  SpeakingTranscriptStrip, SpeakingSessionResultView, and ReportProblemButton.
- Existing DesignTokens and Speak UI components.

Add or adapt after approval:

- A focused SpeakingPracticeScreen for the guided one-prompt loop.
- A shared SpeakingPromptCard for model phrase, target, translation, and hint.
- A SpeakingAttemptFeedback surface for transcript, correction, retry, and
  continue.
- A small state adapter that hands the learner from guided prompts into the
  existing SessionScreen roleplay.

No new package is required for this proposal.

## Data and learning contract

Each guided prompt should carry:

- scenario and learner goal;
- tutor model phrase and audio;
- canonical French target;
- optional English hint;
- accepted response intent or key phrase;
- recorded transcript;
- correction reason;
- next-step action.

Gemini or the app's current lesson agent owns the canonical prompt,
translation, intent, and correction explanation. Audio services render the
tutor phrase and the learner recording remains the evidence for feedback.
Never silently rewrite the learner's transcript into the ideal answer.

## Preserve and do not copy

Preserve:

- the selected tutor persona and stable portrait;
- real microphone state and interruption handling;
- the existing voice disclosure, quota, session recorder, and end-call
  confirmation;
- the current live conversation capability;
- accessible labels, safe areas, and large recording targets.

Do not copy:

- Speak or Busuu logos, exact copy, or proprietary character art;
- a full-screen character as the default drill surface when the target phrase
  would become hard to find;
- an unexplained pronunciation score;
- a flow that makes learners restart the entire lesson after one bad recording.

## Acceptance checklist

- The learner can identify the situation, goal, target phrase, and next action
  without explanation.
- Native model audio is available before recording.
- Record, stop, retry, type fallback, and continue states are distinct.
- The microphone state is visible and honest.
- Feedback shows what the app heard and one useful correction.
- The learner can enter live roleplay without losing the scenario context.
- Settings and More remain in the same top-bar position across all speaking
  states.
- The flow preserves current tutor identity, session persistence, quota, and
  end-call behavior.
- The screen remains useful when network or feedback services are slow.

## Open decisions

1. Should the default speaking entry point be a guided drill or the existing
   free conversation? **Recommendation: guided drill, with Free Talk one tap
   away.**
2. Should the first feedback label be qualitative or numeric?
   **Recommendation: qualitative until pronunciation scoring is validated.**
3. Should the tutor portrait appear in the guided drill? **Recommendation: a
   small tutor identity card, not a dominant full-screen character.**

Waiting for your approval before I edit code.
