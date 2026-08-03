# Phase 5: Voice / Live Call for Web

**Status**: Interface extracted and web implementation written; compiles and playback verified in a real
browser. **Mic capture is NOT yet verified on real hardware** — see "What still needs your hands" below.

Built:

- `lib/services/audio_streaming_service.dart` is now an **abstract interface** with a factory constructor, so
  all 8 existing call sites (`session_screen`, `inline_call_controller`, `lesson_speech_service`,
  `tutor_voice_preview`, `lesson_qa_overlay`, the three `agent_led_*` screens) construct
  `AudioStreamingService()` exactly as before and are completely unchanged. The surface is precisely the 8
  members those callers actually use: `requestPermission`, `startStreaming`, `stopStreaming`,
  `playAudioChunk`, `stopPlayback`, `isOutputActive`, `setSpeakerEnabled`, `dispose`.
- `audio_streaming_service_native.dart` — the original flutter_sound/audio_session implementation, moved
  **verbatim** (class renamed to `NativeAudioStreamingService`, `@override` annotations added, nothing else).
  Every hard-won comment and race fix is preserved. `flutter test` still 192/193 with the same single known
  pre-existing failure, confirming no behaviour change.
- `audio_streaming_service_web.dart` — new Web Audio API implementation:
  - Two `AudioContext`s constructed at 16000 and 24000 Hz so **the browser does all resampling** and there is
    no hand-written interpolation anywhere.
  - Capture via an **AudioWorklet** (not the deprecated `ScriptProcessorNode`), with the processor JS injected
    from a Blob URL so there is no separate `web/*.js` asset to keep in sync. The worklet runs on the audio
    render thread, so frames keep arriving evenly while Flutter lays out a lesson screen; a main-thread
    ScriptProcessorNode drops frames under exactly that load, audible as clipped words.
  - Playback uses Web Audio's **sample-accurate scheduling** (`_nextStartTime` cursor) instead of the native
    implementation's hand-managed drain loop — gapless playback of network-bursty chunks falls out for free.
  - Carries the same two non-obvious behaviours as native: the **odd-byte carry** across chunk boundaries (a
    split PCM16 sample shifts every following sample: gargled audio), and the **playback tail grace** so the
    mic does not reopen into the tutor's still-playing voice. Barge-in stays disabled for the same VAD reason.
- `audio_streaming_service_stub.dart` — loud `UnsupportedError` fallback for a platform matching neither
  conditional-import condition.
- `package:web` promoted from a transitive to an explicitly declared dependency, since it is now imported
  directly.
- `lib/dev/web_audio_check.dart` — dev-only entrypoint to verify this by hand on real hardware.

Verified so far: `flutter analyze` clean; `flutter test` 192/193 (native unchanged); `flutter build web
--release` compiles the whole app including the web audio implementation; and in a real browser the **playback
path runs end to end** — a synthesised 1.5s 440Hz tone pushed through `playAudioChunk` in 38 network-sized
slices queued all 72000 bytes with zero errors or exceptions.

### What still needs your hands

The sandboxed browser used for verification has **no microphone and no WebGL**, so two things are unproven and
must be checked on a real machine before Phase 5 can be called done:

```
flutter run -d chrome -t lib/dev/web_audio_check.dart
```

1. **Playback quality** — press "Play test tone". It should be ONE clean continuous 440Hz tone. Gaps, clicks,
   or overlapping tones mean the scheduling cursor is wrong.
2. **Mic capture** — press "Start mic capture", grant permission, speak. Chunk count and the level meter should
   both move, and on stop the byte total should be roughly `16000 * 2 * seconds`. A byte count far below that
   means frames are being dropped or the output-gate is closing the mic when it should not.
3. **Then the real thing**: a full live call on web, end to end, and an honest judgement on whether browser
   latency is acceptable versus native. That judgement is the actual remaining decision here and it needs
   ears, not tests.

## Why this one is different from every other phase

Every other subsystem in this plan is "same logic, different plumbing underneath, thin shim." Voice is not:
the actual audio capture/streaming pipeline (`flutter_sound`, `gemini_live_service.dart`,
`inline_call_controller.dart`, `inline_call_bar.dart`) is built on native mic APIs that have no direct
equivalent in a browser. This needs an actual new implementation of the streaming layer, not a config switch.

## What stays the same

- The Gemini Live *protocol* logic (what messages get sent, how responses are interpreted, transcript
  handling, the LLM intent judge driving navigation) is not audio-format-specific — it operates on whatever
  audio bytes/chunks it's handed. This layer is shared.
- The call UI (`inline_call_bar.dart`), call lifecycle state machine, and everything in
  `lesson_agent_service.dart` that reacts to call events — shared.
- Card announcements, audio-cut behavior, and the rest of the call UX design — shared; the web
  implementation must produce output the shared logic can't tell apart from native.

## What needs new code

- Audio capture: browser `MediaStream`/`getUserMedia` in place of native mic capture.
- Audio streaming to Gemini Live: Web Audio API (`AudioWorklet` for low-latency processing) in place of
  `flutter_sound`'s native streaming.
- Playback of the model's spoken responses: Web Audio API playback in place of native audio playback.

## Recommended approach

1. Define an `AudioStreamingService` interface covering exactly the operations `inline_call_controller.dart`
   currently calls on the native implementation (start capture, stream chunks out, receive/play chunks in,
   stop). Do this refactor on the *native* side first, with zero behavior change, and get `flutter test`/manual
   verification confirming the native call flow still works identically before adding anything web-specific.
2. Implement the web side against that same interface using Web Audio API. Prototype this in isolation first
   (a minimal test harness that streams mic audio to Gemini Live and plays back a response) before wiring it
   into the full call UI — this de-risks the hardest unknown (real-time audio latency in-browser) before
   spending time on integration.
3. Explicitly test and budget for latency/quality differences. It is reasonable for web voice quality to be
   *good* rather than bit-for-bit identical to native — set that expectation with stakeholders up front rather
   than discovering it under deadline pressure.

## Deliverable

- `AudioStreamingService` interface with a native implementation (refactored from current code, behavior
  unchanged, verified) and a web implementation (new).
- A working, manually-verified live call on web: mic capture, streaming to Gemini Live, spoken response
  playback, transcript/intent-judge navigation all functioning end to end.
- Written note here on any latency/quality gap versus native, and whether it's acceptable for launch.
