# Speaking Character Implementation

Status: 2026-08-16
Decision: keep the app on the stable image-based tutor presentation for now. The experimental lip-sync renderer is no longer used by runtime screens. The AI-generated tutor portraits remain available and are now resolved from the selected tutor.

Related UI proposal: [V3 Speaking Redesign — Speak + Busuu Interaction Contract](flutter_app/V3%20design/speaking%20interaction%20wireframes.md).
That proposal defines the guided speaking drill and roleplay shell before any
new speaking UI code is approved.

## What was tested and why it was reverted

The first prototype drove a painted mouth and a few face layers from PCM amplitude. The next prototype cross-faded a storyboard of still images. Both approaches failed the product bar:

- Full-frame image swaps do not preserve facial geometry, lighting, hair, eyes, or head position. The result reads as jittery image replacement, not a person speaking.
- Amplitude is only loudness. It does not provide phoneme timing, mouth shapes, gaze, blink timing, emotion, or head continuity.
- A custom Flutter-painted puppet was visually disconnected from the generated tutor portraits and looked like a demo control, not a tutor.
- More easing or a longer cross-fade could hide a hard cut, but it cannot turn unrelated frames into a continuous face.
- The local conversation demo (`flutter_app/tool/tutor_conversation_demo.py`) confirmed the failure mode: the audio was plausible while the visual motion was discontinuous and had no reliable relationship to speech.

Conclusion: do not keep patching frame swaps. A production renderer needs either a trained audio-to-face model or a professionally authored 2D rig with phoneme/expression controls.

## Current runtime decision

The app is deliberately back on the previous stable presentation:

1. `ActiveTutor` remains the single persisted selection.
2. `TutorPersona.portraitAsset` is the single portrait registry.
3. Session screens use the persona captured when the call starts.
4. Transcript labels, inline-call labels, history, onboarding, settings, and tutor preview resolve the selected persona instead of defaulting to Marie/Murray.
5. `TutorAvatarStage` renders the selected portrait as a stable image. It keeps the old constructor shape for compatibility, but it does not pretend to perform lip-sync.
6. The experimental storyboard and PCM lip-sync files are retained as research/history artifacts, but are not part of the active runtime path.

This avoids a destructive repository reset because the branch contains other user-owned redesign and curriculum work.

## Research findings

### What Speak and Praktika reveal publicly

[Speak describes its voice-agent platform](https://www.speak.com/blog/building-speaks-voice-agent-platform) around streaming speech recognition, an LLM, speech generation, interruption handling, and a real-time transport layer. Its exact character renderer is proprietary. [Speak's roleplay documentation](https://help.speak.com/en/articles/13182402-free-talk-immersive-roleplay) confirms the product pattern: context, tutor persona, and conversation behavior are part of one live session.

[OpenAI's Praktika case study](https://openai.com/index/praktika/) describes an AI language-learning product built around personalized tutor agents and immersive practice. [Praktika's ElevenLabs case study](https://elevenlabs.io/blog/praktika-scales-immersive-language-learning-with-elevenlabs-tts) confirms its voice stack, while [Praktika 4.0](https://praktika.ai/blog/praktika-4-0) shows the product direction. These sources do not publish a drop-in renderer or a free Flutter package. Their character layer is a product-specific asset and animation system.

### What OpenRouter can and cannot do

[OpenRouter's model catalog](https://openrouter.ai/models/) is useful for selecting an LLM for dialogue, lesson context, and response planning. [Its video-generation documentation](https://openrouter.ai/docs/guides/overview/multimodal/video-generation) describes an asynchronous prompt/image-reference video API. That is not the same as driving an existing tutor face from a live audio stream. OpenRouter should be used for dialogue orchestration only, not treated as the lip-sync renderer.

### Open-source and hosted candidates

| Option | What it solves | Cost / operational reality | Decision |
| --- | --- | --- | --- |
| [MuseTalk](https://github.com/TMElyralab/MuseTalk) | Audio-driven mouth animation for a source portrait/video | Open source, but needs a GPU backend for useful latency | Best first benchmark |
| [LivePortrait](https://github.com/KlingAIResearch/LivePortrait) | Portrait animation driven by motion/expression input | Open source; inference still needs GPU for interactive use | Good for authored motion tests |
| [fal MuseTalk](https://fal.ai/models/fal-ai/musetalk/api) | Hosted MuseTalk with a realtime/WebSocket path | No local GPU; account pricing and limits must be verified | Fastest hosted prototype |
| [Alibaba LivePortrait](https://www.alibabacloud.com/help/en/model-studio/liveportrait-quick-start/) | Portrait plus audio to dynamic portrait video | Published rate is about `$0.002868/sec`, approximately `$0.172/min`; async and concurrency limits apply | Clear official low-cost option |
| [FairStack MuseTalk 1.5](https://fairstack.ai/models/musetalk-1.5) | Hosted MuseTalk endpoint | Advertises about `$0.0015/sec`, approximately `$0.09/min`; third-party claim, test reliability and commercial terms | Cheapest advertised test |
| [North Model Labs](https://www.northmodellabs.com/pricing) | Hosted realtime avatar passthrough/WebRTC | Advertises about `$0.117/min`; suitable for a fast proof of concept | Simple fallback |
| Self-host on [RunPod Serverless](https://docs.runpod.io/serverless/pricing) | Full control over MuseTalk/LivePortrait | Pay-per-second GPU and scale-to-zero; cold starts, storage, queueing, and ops remain | Cheapest at sustained volume if engineered well |
| Self-host on [Modal](https://modal.com/pricing) | Managed GPU functions with scale-to-zero | Starter credits help testing; L4/T4 rates are published, but platform code is required | Good engineering option |
| [uLipSync](https://github.com/hecomi/uLipSync) / [Rhubarb](https://github.com/DanielSWolf/rhubarb-lip-sync/blob/master/README.adoc) | Local phoneme/lip-shape analysis for authored rigs | Free/open source, but only as good as the 2D/3D rig it drives | Good for a deliberately authored rig |
| [Rive runtime](https://rive.app/docs/runtimes/getting-started) / [TalkingHead](https://github.com/met4citizen/TalkingHead) | Interactive 2D/vector or WebGL character systems | Runtime may be free, but authoring, asset work, and integration are not zero-cost | Consider only for a new authored style |

There is no credible “free in production” option for realistic arbitrary face animation. Open-source code can be free while GPU compute, hosting, storage, and engineering are not.

## Cheapest viable production approach

The recommended path is a hybrid, not per-frame image generation:

```text
Gemini or OpenRouter
  -> response text + turn metadata
  -> TTS audio stream
  -> MuseTalk/LivePortrait service
  -> short video/WebRTC stream
  -> Flutter video surface
```

For the first production experiment:

1. Create one consistent, front-facing Camille source clip with a neutral listening pose, natural blink, breathing, and subtle head motion.
2. Send only the generated tutor audio to MuseTalk or LivePortrait; never generate a new image for every frame.
3. Keep three authored states: listening, speaking, and thinking. The model handles mouth movement; authored transitions handle the rest.
4. Use a stable WebRTC/video surface in Flutter. Treat each tutor turn as a cancellable job with a turn id so an interrupted response cannot replace the next response.
5. Measure first-turn latency, mouth alignment, dropped frames, cancellation correctness, and cost per minute before expanding to Julien, Camille, Marie, and Mathieu.

The lowest-risk hosted trial is FairStack or fal. The lowest long-run unit cost is likely a scale-to-zero RunPod worker running MuseTalk, but only after a benchmark proves the GPU and queue setup. Alibaba LivePortrait is the cleanest official price reference for a quick cost model.

## Acceptance tests before enabling it in the app

- The same face identity, hair, eyes, lighting, and shoulders remain continuous through a 30-second tutor turn.
- Mouth motion starts within an acceptable latency of audible speech and stops with the audio.
- A quiet pause does not create random mouth movement.
- Interrupting Camille immediately cancels Camille's audio and video job; Julien cannot inherit stale frames.
- Switching tutor selection changes the source portrait and voice together.
- A 3-minute session completes without jitter, frozen frames, visual drift, or overlapping audio.
- A repeated test on a low-power iPhone remains usable over Wi-Fi.
- Cost is measured from actual generated seconds, not a vendor estimate.

## Future implementation contract

Do not merge a talking-character backend until it passes the acceptance tests above. Keep the stable portrait fallback available when the service is unavailable, slow, or cancelled. The app must always be useful as a language lesson even if animation is disabled.

The next implementation should be a standalone Camille-only adapter with mocked Gemini/TTS input, followed by one real hosted endpoint. It should expose only:

- `startTurn(turnId, audioStream, persona)`
- `cancelTurn(turnId)`
- `onVideoChunk`
- `onStateChanged`

This keeps the renderer separate from curriculum, transcript, tutor selection, and billing. Once the adapter is reliable for Camille, add the other three personas through the same source-asset contract.

## Reversion record

Reverted from the active runtime:

- PCM-amplitude mouth painting
- canvas-based puppet layers
- storyboard pose cross-fades
- runtime use of the experimental lip-sync controller

Kept intentionally:

- AI-generated tutor portrait assets
- tutor conversation demo and storyboard files for future comparison
- the compatibility `TutorAvatarStage` widget
- the selected-tutor persistence and portrait mapping

This is the current safe baseline: correct tutor identity everywhere, stable visuals, and no false claim that the app has production-grade lip-sync.
