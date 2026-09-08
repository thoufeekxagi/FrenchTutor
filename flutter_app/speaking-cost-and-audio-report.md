# Speaking lesson cost and audio report

Updated 2026-09-07. This report describes the code path used by the Course
guided-speaking lesson and the authored Unit 1 speaking lesson. It is based on
the Flutter source and Supabase function source; exact provider currency is
only available from Google's usage metadata/billing export.

## What changed in this pass

- The speaking helper starts enabled on a fresh install.
- The old switch is now a phone button. It is green only when the Live socket
  is active. Tapping it starts or ends the existing helper call.
- A saved learner choice still wins. If an existing install previously saved
  Speaking help as Off, the phone remains off until the learner taps it.
- Speaking does not require a pre-generated audio deck. If the optional offline
  replay cache has no clip, the screen now says exactly `Tap phone for live
  guidance.` The phone opens the existing Live tutor path; it does not trigger
  a hidden synthesis request.
- Guided Speaking now uses one compact Live system contract for the whole
  lesson. The socket stays open, but each Next action sends only the replacement
  current-step payload; it does not resend the full lesson or learner profile.
- Guided Live compression is 2,000 tokens with a 1,000-token sliding target.
  Free Talk and Roleplay keep their existing conversation contract.
- Speaking lesson generation is explicit and single-attempt. Opening the
  Speaking catalog, changing mode, and completing a lesson no longer trigger
  automatic reserve generation.

## Guided speaking with the phone connected

1. `SpeakingLessonFlowScreen` creates one `InlineCallController`.
2. The controller requests one short-lived Live credential through Supabase's
   Gemini token function and opens one `GeminiLiveService` WebSocket.
3. The Live setup uses `gemini-3.1-flash-live-preview`, a compact guided
   speaking prompt, input/output transcription, and context-window compression
   at a 2,000-token trigger with a 1,000-token retained window. The socket stays
   open for the lesson.
4. For guided speaking, the microphone is muted while the tutor is idle. It is
   opened only after the learner taps Record and closed when Stop is tapped.
5. Gemini Live returns the input transcription on that same socket. The app
   folds accents and punctuation and checks the transcript locally with exact,
   containment, or 72% target-word overlap rules. This is what turns the card
   green; there is no separate Gemini grading request for this check.
6. The same Live socket may speak one short correction/encouragement. That
   response is the Live audio cost for the turn. There is no extra Flash
   grading call in this path.

When the learner taps Next, the app sends a small replacement note containing
only the new step number, level, French target, English meaning, and optional
pronunciation tip. The prompt explicitly treats that note as the active screen;
the app does not append the entire lesson context again. Compression is the
actual server-side history control—telling the model to forget something alone
would not erase billed history.

The controller closes the socket when the route is disposed, the app is
backgrounded, or the manual idle limit is reached. The Live service has one
bounded reconnect for a genuine network loss; it does not run a background
retry loop.

## Guided speaking with the phone disconnected

The lesson still uses the local scripted check, but it needs two different
local/provider paths:

- Prompt playback may read an optional PCM cache. A cache hit is local playback
  and costs zero provider calls. Speaking content itself is not blocked on that
  cache.
- If the optional clip is absent, the UI says `Tap phone for live guidance.`
  This screen does not silently synthesize a replacement.
- Recording captures 16 kHz PCM locally for up to six seconds. On Stop, one
  `ai-text` request asks `gemini-3.1-flash-lite` to transcribe the short clip,
  with a 220-token output cap. The app then applies the same local match rule.

Therefore the green result seen with the helper off is not Gemini Live grading.
It is Gemini Flash-Lite transcription followed by deterministic local matching.
With the helper on, it is Live input transcription followed by the same local
matching. In neither case does this speaking card call the separate
`judgePronunciationAttempt` enrichment method.

## Prepared and generated lesson audio

`LessonAudioDeckService.prepare` is the only owner of personalized sentence
audio preparation. For every segment it checks, in order:

1. the local PCM cache;
2. the private Supabase Storage mirror;
3. one explicit `GeminiLiveAudioService.generateAndCache` call only for a true
   miss during an explicit preparation transaction.

Missing segments are serialized, so a five-line lesson does not open five Live
sockets at once. A generated clip is written as raw PCM16 locally and mirrored
to Supabase as `pcm_s16le+gzip`; SQLite stores the lesson/segment manifest.
Reading or replaying a ready clip does not run gzip live and does not call
Gemini. Gzip is only the storage encoding/decoding step around the already
generated bytes.

Authored shared course audio is cheaper: Unit 2's shared WAV is downloaded,
validated, and sliced locally. That import records zero provider calls. Unit 1
alphabet audio is bundled with the app and prewarmed into the local cache; its
speaker buttons never use Gemini.

## Where the cost is visible

The app records the provider-reported values rather than guessing a dollar
amount:

| Path | Provider/model | Calls on a cache hit | Usage evidence |
| --- | --- | ---: | --- |
| Live tutor | Gemini 3.1 Flash Live | 0 while disconnected; 1 socket while active | `live_usage_metadata`, `live_session_socket_closed`; prompt/response/total tokens and input/output audio seconds |
| Offline speaking check | Gemini 3.1 Flash-Lite | 1 transcription request per recorded attempt | `speech_transcription_requested` / `finished`; PCM byte count and transcript length |
| Personalized PCM preparation | Gemini 3.1 Flash Live audio | 0 if local/cloud clip exists; 1 bounded generation per missing segment | `audio_generation_requested`, `live_audio_usage_metadata`, `live_audio_generation` |
| Shared/authored PCM | Supabase Storage + local SQLite | 0 | `shared_course_audio_imported` with `provider_calls: 0` |
| Guided Speaking lesson generation | OpenRouter GPT-5.6 Luna | 1 explicit request; no automatic reserve or app retry | text provider usage with the speaking generation trace |
| Course text authoring | Existing explicit text-generation route | 1 per explicit Generate action | `traceFeature` and provider usage from the Edge Function |

The provider usage metadata is the authoritative token count. Local
`AiCostTracker` events are a call ledger, not a replacement for Google's bill.
In particular, a failed provider attempt is marked billing-unknown because a
network failure does not prove that Google received zero input.

## Practical interpretation of the screenshots

The old red message shown with Marie help Off was caused by a missing optional
phrase replay clip. It was not a hidden Live grading request and it was not
Alphabet audio. The corrected message now gives the only useful action: tap the
phone for live guidance.
