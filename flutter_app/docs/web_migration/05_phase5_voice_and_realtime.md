# Phase 5: Voice / Live Call for Web

**Status**: Not started. This is the hardest phase — budget it as its own scoped effort, not a checkbox
alongside the others. Do not attempt this before Phases 1-3 are stable; you want a solid, tested foundation
under this before tackling the riskiest subsystem.

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
