# Marie voice review — 15 October 2026

Historical snapshot only. Its blanket half-duplex rule and 900 ms output tail
were replaced for the V3 lesson tutor on 18 October. Read
[`MARIE_VOICE_ARCHITECTURE.md`](MARIE_VOICE_ARCHITECTURE.md) for the current
Gemini-first design and verification status.

## Executive decision

The lesson tutor now uses Gemini 3.8 Live through a dedicated deployed
v1beta ephemeral-token function. Its mic dispatch rejects tutor output, the
playback tail, clips, and short noise bursts before network transmission. Its
reply contract is short and learner-directed. Existing non-lesson Live calls
remain on 3.1 and their existing token path. Google's listed audio-token
price is the same for both models. A tenfold improvement cannot be claimed
until baseline and candidate calls are scored on the same physical devices.

The product rule that no microphone audio reaches a model while the phone
makes sound excludes full duplex model interruption. A local interruption
detector may eventually stop playback, clear its queue, wait out the 900 ms
tail, and then open the mic. It must never stream the interruption audio while
playback is active. The existing Skip button is the deterministic escape.

## Current system, high level

`V3LessonPlayer` owns `V3LiveMarieSession`; it lazily creates
`InlineCallController`, which owns `GeminiLiveService` and
`AudioStreamingService`. The selected persona supplies the voice. A phone tap
opens a conversation with a short greeting. A speaker tap opens a muted call
and asks Live to say the exact authored text. Screen changes refresh context
and cut stale replies. Reconnect includes a short transcript memory.

## Current system, mid level

| Layer | Current behavior | Limit |
|---|---|---|
| Input | `flutter_sound` records 16 kHz mono PCM. iOS session is `playAndRecord` / `voiceChat`; Bluetooth route changes reactivate it. | `voiceChat` mode alone does not guarantee VoiceProcessingIO echo cancellation. Route behavior needs physical proof. |
| Turn start | Gemini automatic VAD: low start sensitivity, 300 ms prefix padding. The existing local amplitude gate was unused for lesson calls before this change. | Amplitude is not speaker identity. Quiet French and noisy rooms need measured false-start/miss rates. |
| Turn end | Gemini automatic VAD waits 1,300 ms in lessons. A local speech-end callback exists but is not wired for this call. | Fixed silence cannot reliably infer whether the learner is thinking mid-sentence. |
| Playback | 24 kHz PCM is fed through a serialized queue. The echo gate blocks while output is active, through scheduled playback, and for a 900 ms tail. App clips extend the same window. | Scheduled duration is an estimate, so device timing must be measured against audible output. |
| Response | `compactLessonCoach`, minimal thinking, 1,000 output-token ceiling. Current step and six call-memory lines survive reconnect. | A ceiling is not a short-response target. The prompt now makes direct answers and pace requests explicit, but model behavior needs human evaluation. |
| Cost | 3,000-token compression trigger, 1,500-token target; 90 s talk idle limit; local `AiCostTracker`. | The local cost estimate does not capture all context re-billing or transcription charges. Reconcile with provider usage. |

## Changes in this pass

1. `AudioStreamingService` applies `MicEchoGate.blocks` before every local
   input mode. No amplitude-based interruption path can bypass the output or
   clip window. It also clears partial speech candidates during that window.
2. Lesson calls use the existing local speech-start gate. It requires roughly
   200 ms of sustained level above its adaptive floor and keeps a 280 ms
   pre-roll. Gemini automatic VAD remains the turn-end authority. This filters
   steady low-level room noise and short clicks; it does not identify speakers.
3. The lesson prompt asks for a direct one-sentence reply to simple requests,
   repeats only what was requested, and retains a requested slower pace.
4. Lesson setup uses `models/gemini-3.8-live` and proactive audio, without the
   3.1-only thinking field. A new `gemini-live-v3-token` Edge Function is
   deployed ACTIVE with JWT verification and issues v1beta, single-use,
   model-constrained tokens. Other calls retain the established v1alpha path.
5. The socket cost event records direct audio cost as a lower bound instead
   of charging provider token totals again as text. Full cost still requires
   reconciliation with provider billing, including context and transcription.
6. Automated checks pass: 40 targeted Flutter tests, the quick code/content
   gate, Deno type check and token request test, and an unauthenticated remote
   request correctly returned HTTP 401. The French synthetic PCM replay test
   confirms playback blocking and post-tail admission in the real dispatch.
   No physical iPhone or simulator runtime was available for acoustic proof.

## Next engineering steps, in priority order

### 1. Instrument real calls before tuning further

Record metadata only by default: route, timestamp of speech candidate, first
forwarded PCM, server speech start/end, first audio received, first audible
audio, turn complete, last audible audio, dropped mic bytes by reason, Skip,
interruption, reconnect, output seconds, usage tokens, and session cost. No
raw speech should be retained without explicit test consent. Measure from the
user's end of speech to first audible answer, not just socket arrival.

### 2. Build an audio evaluation set

Use the same 30–50 scripted turns on loudspeaker, earpiece, wired headset,
AirPods, and route switching, across quiet room, café/TV, another speaker,
clips, and deliberate pauses. Include A1 accented French, whispers, and
longer B2 questions. Have a human label who spoke and whether Marie's answer
was relevant, concise, accurate, appropriately paced, and safe. Replay
consented PCM through a pure input policy test harness, then run live device
tests for native routing. Target zero self-echo responses; report confidence
intervals rather than assuming one clean run proves zero risk.

### 3. Compare models and turn policies

Google currently recommends Gemini 3.8 Live over the legacy 3.1 preview and
lists both at the same audio token price. 3.8 adds proactive audio, which can
choose silence for irrelevant input, and supports mid-session client content.
The model change is scoped to lesson calls. Run paired evaluations of 3.1 and
3.8 with identical prompts,
voice, device, and test audio. Check 3.8 setup and server event parsing before
any rollout; its thinking configuration differs. Compare proactive audio on
and off because silence behavior and input cost need evidence.

Try Google's documented hybrid VAD only after the local detector is measured.
It keeps server speech-start detection and sends `audioStreamEnd` on a confident
local end. Use a longer pause for novice French and retain server VAD as a
fallback. Do not infer the end from one low-volume packet.

### 4. Improve acoustic separation and interruptions

Investigate a native VoiceProcessingIO / AVAudioEngine voice-processing path
with the actual playback reference signal. Apple's documentation says
`voiceChat` without Voice I/O or voice-processing-enabled AVAudioEngine does
not provide the full voice-specific processing, including echo cancellation.
Test any native path on every route; keep `MicEchoGate` as the final guard.

Local barge-in can stop playback after strong near-field speech evidence, then
wait for the output tail and capture a fresh learner turn. It cannot promise
to preserve the first syllable under the current hard rule. The user-visible
Skip control remains the reliable way to interrupt immediately.

Rejecting *other people* requires more than VAD or a prompt. Optional local
speaker verification could enroll the learner with clear consent and make a
conservative allow/abstain decision. Test it against family voices, TV speech,
AirPods, illness, accents, and device changes. Until accuracy is proven, offer
tap-to-talk in noisy environments instead of silently discarding legitimate
learner speech.

### 5. Control answer quality

Use a small intent rubric in evaluation: answer/repeat/slower/spelling/
pronunciation/stop/clarify. The model should answer the latest request once,
then wait. For pronunciation feedback, require an actual distinct attempt;
when audio is unclear, ask for one retry. Measure median and p90 spoken words
per simple answer and the rate of unrequested follow-up questions. Prompt text
is a policy hint, not enforcement; if long replies persist, add a bounded
per-turn response controller or an explicit short-answer tool protocol only
after device tests show it works with audio generation.

## Cost accounting

The current published rate for 3.1 and 3.8 Live is $3 per million input audio
tokens (about $0.005 per input minute) and $12 per million output audio tokens
(about $0.018 per output minute), plus text and transcription charges.
These minute equivalents are not a flat session price: Google's Live guide
says prior raw audio in the active context is re-billed on later turns. The
existing 3,000/1,500 compression policy and closed mic during output are
material savings. Compare actual provider usage per *successful helpful turn*,
including failed turns, rather than cheapest model price alone.

## Verification matrix and release gate

| Test | Automated | Physical device / human |
|---|---|---|
| Mic gate during tutor, queued playback, tail, app clip | Unit | Capture PCM/network trace on each route |
| Noise gate, click rejection, quiet speech, pre-roll | PCM fixture unit | Human-labelled room recordings |
| Phone, speaker, mute, Skip, screen change, reconnect | Widget/fake integration | Real Live call |
| Direct, short, paced responses and pronunciation honesty | Prompt contract test | Blind human scoring of paired calls |
| Cost and latency | Event schema test | Provider usage reconciliation and audible timing |

Release only after the real-device matrix shows no self-echo response, no
regression in quiet learner recognition, and a statistically credible gain in
helpful-answer rate. A tenfold claim requires a defined baseline metric, such
as unwanted replies per 100 turns or cost per successful turn; neither is
measured yet.

## Primary sources checked 15 October 2026

- [Google Live capabilities and model comparison](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Google ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens)
- [Google Live WebSocket endpoint](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)
- [Google Live VAD and hybrid VAD](https://ai.google.dev/gemini-api/docs/live-api/capabilities#voice_activity_detection_vad)
- [Google Live best practices and context billing](https://ai.google.dev/gemini-api/docs/live-api/best-practices)
- [Google model pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Apple voiceChat audio processing behavior](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat)
- [OpenAI Realtime turn detection, semantic VAD, and noise reduction](https://platform.openai.com/docs/guides/realtime-vad)
