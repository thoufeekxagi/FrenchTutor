# Marie voice architecture

Updated 18 October 2026. This is the current Gemini-first design for the
interactive lesson tutor and Live Tutor. The 15 October review remains as a
historical record; its blanket playback gate and 900 ms tail are no longer the
V3 interaction policy.

## Product behavior

Marie should behave like a French teacher working beside the learner:

- Answer the latest request directly, then make one useful teaching move.
- Use the lesson step and recent attempts as context, but do not narrate the
  lesson or force the learner back to it when they ask a real question.
- Give one correction at a time. Let the learner retry before taking over an
  exercise. Honor direct requests for an answer, translation, repeat, or slower
  speech.
- Use English scaffolding at A1/A2 and mostly French at B1/B2. Ask at most one
  question per turn, then wait.
- Stop the current answer when the learner interrupts. Ignore unclear noise
  rather than guessing at what was said.

The app sends the visible lesson state and a short same-call memory. The tutor
does not own lesson progression or hidden quiz answers.

## Runtime path

```text
iPhone mic -> VoiceProcessingIO / AVAudioEngine -> 16 kHz PCM -> local VAD -> Gemini Live WebSocket
Gemini Live WebSocket -> 24 kHz PCM -> same AVAudioEngine output node -> iPhone speaker/headset
```

On iOS, `VoiceProcessingAudioPlugin` enables voice processing on the input node
and routes Marie's playback through the same engine. That gives the AEC a render
reference while capture remains active. Both the interactive lesson and Live
Tutor use this path so confirmed learner speech can interrupt Marie. App-owned
lesson clips keep a measured local mute window with a 150 ms output tail. If the
native engine cannot start or recover, the service uses its conservative
half-duplex fallback.

On Android, these calls use flutter_sound's `voice_communication` audio source
with platform AEC/NS enabled. This route has not yet had physical-device
verification in this pass.

`VoiceActivityGate` is deliberately a small transport gate, not speaker
recognition. It requires 180 ms of sustained speech, keeps up to 240 ms of
pre-roll, forwards the learner segment plus 700 ms of ending silence, then sends
Gemini's `audioStreamEnd`. Gemini automatic VAD remains enabled at 850 ms as a
second boundary check. Short silence and clicks do not open a billable turn.
The tutor output is stopped locally as soon as learner speech is confirmed;
when Gemini acknowledges interruption, stale output is discarded.

## Cost controls

- Gemini Live is the active provider. GPT-Live is a candidate only if a paired
  device evaluation shows Gemini misses the quality bar; it is not a default or
  currently wired fallback.
- Send only locally detected learner turns, not open-mic room silence. The
  90-second idle hangup limits a connected but unused lesson call.
- Keep ordinary spoken replies short. Output ceilings are 1,000 tokens for the
  in-lesson coach and 2,000 for Live Tutor; they do not add cost unless the
  model generates that audio.
- Lesson and Live Tutor context compression triggers at 4,000 tokens and
  targets a 2,000-token sliding window. Recent turns and current app state are
  kept separate so the latest step can replace stale details.
- `AiCostTracker` records PCM seconds and provider-reported token counts. Its
  direct-audio estimate is a lower bound; transcription and context charges
  must be reconciled against Google's usage dashboard.

The published Gemini 3.8 Live rates are $0.005 per input-audio minute and
$0.018 per generated-audio minute, before text transcription and context
charges. The local VAD keeps silence off the socket, so the app does not stream
the room continuously. Actual cost depends on usage, not a flat call price.

## Public implementation references

OpenAI's public Live API guides describe full-duplex audio, client media tracks,
barge-in and WebRTC as the recommended mobile/browser transport. They document
how to build a compatible product; they do not disclose ChatGPT's private app
implementation. We borrow the public interaction principles—keep media moving,
stop queued output on barge-in, preserve app-owned context, and keep prompts
short and operational—while using Gemini as the lower-cost provider.

Google's public Live API guidance covers 16 kHz PCM input, 24 kHz PCM output,
server VAD, client `audioStreamEnd`, context compression, interruption events
and ephemeral tokens. Open-source audio stacks such as WebRTC Audio Processing
provide AEC, noise suppression and gain control. LiveKit and Pipecat expose
Gemini Live integrations for WebRTC/server pipelines; we keep the mobile client
direct-to-Gemini to avoid adding a media server and another recurring service.

The `flutter_sound` documentation exposes Android PCM-stream AEC/NS and an iOS
voice-processing flag, but a separate recorder/player path does not guarantee
that playback is the AEC reference. The new iOS route shares an audio engine to
make that relationship explicit.

## Verification status

- Pure local VAD tests cover silence suppression, click rejection, pre-roll,
  endpoint timing and pauses shorter than the endpoint.
- Existing Gemini protocol tests cover setup, transcription, interrupt events,
  and output chunks.
- `integration_test/voice_processing_test.dart` runs on the iPhone through
  `AudioStreamingService`; it checks that mic PCM continues while tutor PCM is
  playing and a reply is pending, then stops after mute. It makes no provider
  request and costs nothing.
- `integration_test/v3_marie_test.dart` checks lesson controls with fake Marie;
  it does not prove provider quality.
- A real Gemini call is required to measure French understanding, barge-in,
  echo rejection and cost per helpful turn. Report that separately from fake
  UI and audio-engine tests.

## Sources

- [OpenAI Live API](https://developers.openai.com/api/docs/guides/live)
- [OpenAI WebRTC voice sessions](https://developers.openai.com/api/docs/guides/voice-webrtc)
- [OpenAI Live prompting](https://developers.openai.com/api/docs/guides/live-prompting)
- [Gemini Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Gemini Live best practices](https://ai.google.dev/gemini-api/docs/live-api/best-practices)
- [Gemini Live pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [flutter_sound 9.30.0 API](https://pub.dev/documentation/flutter_sound/9.30.0/public_flutter_sound_recorder/FlutterSoundRecorder/startRecorder.html)
- [flutter_sound iOS voice-processing discussion](https://github.com/Canardoux/flutter_sound/issues/1109)
- [Reflection Flutter/Gemini Live production notes](https://www.reflection.app/blog/building-real-time-voice-ai-with-gemini-live-api-and-flutter)
