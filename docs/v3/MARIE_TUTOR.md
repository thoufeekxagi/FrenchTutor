# Marie, the in-lesson tutor (design, decisions, risks)

One doc for everything about the live tutor inside lessons: what it should
feel like, how it is built, the numbers, the rules that must never break, the
bugs that taught us each rule, and what is still uncertain. The rules are also
listed in `AGENT_RULES.md` sections 7 to 9; this file explains why.

## 1. What the owner wants

- The tutor sits **on the same screen** as the lesson. Never a new full-screen
  route (the old "Ask Marie" opened a legacy screen and that was rejected).
- A **phone** button, not a microphone. Tap to call, tap again to end. While
  connected: Mute, End, Skip.
- First thing she does when she connects: a short hello so the learner knows
  she is there ("connected, ask me anything"). After that she minds her own
  business until spoken to.
- She behaves like a good human tutor: listens first, answers what was
  actually asked in a few natural sentences, asks one short question only if
  unclear, goes longer only when the question needs it. She is **not fenced
  in** to the current card: real questions always get real answers.
- She teaches pronunciation and checks it: specific feedback on a real attempt,
  no invented praise, no scores.
- The learner can **see what she says** (spelling, missed words) in a small
  pill of at most three lines; tapping it shows the whole conversation.
- Cheap and stable: small prompt, small context, no repeated resets, no
  introducing herself again after a reconnect.
- The learner can interrupt on supported AEC/NS routes; app-owned clips still
  close the mic for their measured length and short output tail.
- The speaker buttons use the same tutor voice, so changing tutor changes every
  voice.

## 2. Architecture

```
V3LessonPlayer (lib/v3/lesson/v3_lesson_player.dart)
  owns a V3MarieSession (created lazily, disposed with the screen)
  V3Speaker taps        -> session.speak(context, text, reveal: ...)
  phone button          -> session.toggle(context)
  step changes          -> session.screenChanged()     (cut old reply, silent context refresh)
  answer checked        -> session.screenUpdated()     (silent context refresh)
  lifecycle             -> session.handleLifecycle(state)   (end only on paused or hidden)

V3MarieSession (lib/v3/marie/v3_marie_session.dart)
  base: caption, history (last 12 lines), speakingText, idle timer, hidden transcript
  V3LiveMarieSession    wraps InlineCallController (real Gemini Live)
  V3FakeMarieSession    scripted, for tests; debugSay / debugLearnerSays / debugLog

UI (lib/v3/marie/v3_marie_dock.dart)
  V3MarieCallButton     top right of the lesson, phone icon
  V3MarieDock           status, Skip, Mute, End, and the response pill
  showV3MarieTranscript bottom sheet: her words and how she heard the learner

Engine (shared with the old app, extended additively)
  InlineCallController  lib/services/inline_call_controller.dart
  GeminiLiveService     lib/services/gemini_live_service.dart   (LiveSessionType.lessonCoach)
  LivePrompts           lib/prompts/live_prompts.dart            (compactLessonCoach)
  AudioStreamingService lib/services/audio_streaming_service.dart + mic_echo_gate.dart
```

Both the in-lesson tutor and full-screen Live Tutor use
`models/gemini-3.8-live` over the v1beta ephemeral-token path. Other established
speaking modes retain their tested Gemini 3.1 contract.

## 3. Two ways a call starts

| | Phone button ("talk") | Speaker tap ("audio") |
|---|---|---|
| Hello | yes (one short English line) | no |
| Microphone | open, auto turn-taking | closed (muted) until the learner unmutes |
| Idle hang-up | 90 s without speech | 270 s (nothing is billed while muted) |
| Purpose | conversation, questions, pronunciation | say this exact line in the chosen tutor's voice |

The speaker command is deliberately tiny: "say only the exact French text
below once, clearly ... EXACT TEXT: ...". It is sent with `promptTutor`, which
queues behind her current speech and uses the realtime-text path supported by
Gemini 3.8 Live.

An unanswered listening question is spoken with `reveal: false`: heard, never
shown in the pill or the conversation sheet, so the text cannot give the
answer away.

## 4. Behaviour and cost settings (all in `gemini_live_service.dart`)

| Setting | Value | Why |
|---|---|---|
| Prompt | `compactLessonCoach` (about 450 words, plus the persona and content-safety blocks) | small fixed cost; re-billed every turn |
| Context window compression | trigger 4,000 tokens, target 2,000 | preserves useful recent turns and keeps repeated context bounded |
| End-of-speech wait | 850 ms for lesson coach, 900 ms for Live Tutor; both use a 700 ms local endpoint | server setting is a fallback after the local endpoint |
| `maxOutputTokens` | 1,000 for lesson coach; 2,000 for Live Tutor | a ceiling, not a target; billing follows generated audio tokens |
| Thinking | model default; `thinkingLevel` omitted | required by the Gemini 3.8 Live setup contract |
| Proactive audio | enabled for both tutor sessions | lets the model stay quiet on irrelevant input; it does not replace local VAD or AEC |
| Reconnects | up to 3 with 1, 2, 4 s back-off (others: 1) | one blip must not kill the call |
| Server connection reset (about every 10 min) | wait for her to finish the sentence, then reconnect | never swap mid-sentence |
| Idle | 90 s (talk) / 270 s (audio only) | no billing for a forgotten call |

Google's current Gemini Live price page lists audio at about $0.005 per input
minute and $0.018 per generated minute for these Live models. Active session
context is billed again on later turns, and enabling input/output transcription
adds text-token charges. The local speech gate keeps silence off the socket;
context compression bounds repeat input. `AiCostTracker` records usage for
comparison against the provider dashboard.

## 5. Context: what she knows and how it stays right

- **Screen snapshot** (`_marieContext()` in the lesson player): learner level,
  lesson title and step number, the visible content, and for questions whether
  they are answered. For an unanswered question: "do not reveal the answer".
  Bounded (long text cut at about 700 characters).
- **Silent updates**: on every step change `updateLessonContext()` sends the
  new snapshot as a silent note (no reply). The note starts "CURRENT APP STEP
  (the screen changed; this replaces every earlier step)".
- **Setup context is rebuilt on every connect and reconnect**
  (`GeminiLiveService.lessonContextBuilder`). A frozen string made her describe
  the first word after any reconnect.
- **Call memory**: `V3LiveMarieSession.withMemory` appends the last six lines
  of the call to the setup context, and the prompt says the call is continuing.
  She never greets again after a reconnect.
- **Stale replies**: moving on while she speaks calls `interruptTutorReply()`
  (drops buffered audio and the transcript) and clears the pill.
- We do **not** send the whole lesson or the whole transcript each time.

## 6. Echo control and full-duplex interruption

The V3 lesson route keeps capture active during tutor playback only when a
platform AEC/NS path is active. On iOS, `VoiceProcessingAudioPlugin` shares one
`AVAudioEngine` between mic and tutor output. On Android, the recorder uses the
communication source with AEC/NS. `VoiceActivityGate` filters silence and short
bursts, preserves speech pre-roll, and closes each learner segment with
`audioStreamEnd`; Gemini server VAD remains enabled too. On confirmed learner
speech, the app stops local playback and drops stale generated audio until
Gemini acknowledges interruption.

Known app-owned clips still use `MicEchoGate` and `blockMicUntil` for the clip's
measured duration plus a 150 ms tail. If full-duplex voice processing cannot
start or recover, the call falls back to half duplex before forwarding raw
audio. Unit coverage for the local gate is in `voice_activity_gate_test.dart`
and `mic_echo_gate_test.dart`; `integration_test/voice_processing_test.dart`
checks the service's iPhone capture/playback path without opening a billable
Gemini session.

## 7. Bugs and what fixed them

| Symptom | Cause | Fix and guard |
|---|---|---|
| "Ask Marie" opened a full-screen legacy call | `V3LessonPlayer._askMarie` pushed `SpeakingPracticeScreen` | inline `V3MarieSession`, dock and pill; no route |
| She replied with long generic speeches | free-talk prompt, A1 word-by-word glosses, a kickoff that said "help with this step" | `compactLessonCoach`, listen-first rules, hello only on connect |
| She praised her own voice | echo entered the learner stream | shared iOS voice-processing engine, platform AEC/NS, local VAD, explicit clip gating |
| Speaker said "Played" but nothing played, then "Check your connection" | speaker generated a clip live on tap and locked the one-shot button before success | speakers ask the tutor on the warm call; lock only after she was reached |
| She talked about the previous word, restarted, introduced herself | context frozen at connect, no memory on reconnect, server reset mid-sentence | builder per setup, call memory, graceful goAway, 3 reconnects |
| Pill could reveal a listening answer | transcript shown | `reveal: false` |

## 8. Known uncertainties and next options

1. **Mid-call silent context updates on Gemini 3.8 Live.** Google's current
   Live API guide supports client content updates during a session. Keep the
   existing protocol test and verify updates in the device call; if wrong-step
   answers return, inspect `live_reconnect_scheduled` reasons first. A quiet
   reconnect with the latest snapshot and call memory remains the fallback.
2. **Gemini 3.8 Live behavior**: both tutor surfaces now use the current model
   and v1beta token path. Its proactive audio can stay quiet on irrelevant
   input, but physical testing still needs to measure tone, latency, false
   starts, interruptions, and cost before we claim a quality improvement.
3. **Story reader** has no inline Marie yet (it has live narration only). Reuse
   `V3MarieSession`, but the narration and the call must share one socket; use
   the controller's external-playback bridge.
4. **Hybrid VAD** (on-device voice detection to send `audioStreamEnd`
   immediately) is an optional improvement. It needs a package (`vad`, Silero
   via ONNX); check app size and iPad memory (the iPad 7th generation killed a
   test at about 1.85 GB).
5. Alternatives considered and not chosen: OpenAI Realtime (about ten times the
   audio price, would lose the four Gemini voices and need a protocol rewrite),
   LiveKit or Pipecat (needs a server), local speech to text (corrects the
   learner's mistakes, defeats pronunciation checking).
6. **Pronunciation feedback is the model's opinion**, not a score. Keep the
   wording honest. A fluent speaker should review real sessions.

## 9. Tests

`test/v3_marie_session_test.dart` (call states, speak, reveal, idle, memory),
`test/v3_marie_ui_test.dart` (panel, pill at three lines, sheet, Skip, size
matrix), `test/v3_marie_in_lesson_test.dart` (live call in the lesson player,
speaker tap asks Marie), `test/mic_echo_gate_test.dart`,
`integration_test/v3_marie_test.dart` (device, fake, no billing). Real
behaviour is checked with the manual script in `FAST_ITERATION_TESTING.md`
section 8.
