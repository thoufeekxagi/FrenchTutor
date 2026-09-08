# Vocabulary generation plan

This is the next development-only Course lane. It follows the verified
Speaking implementation instead of creating a new AI pipeline.

## Goal

Generate one personalized Vocabulary lesson after the authored Unit 2
Vocabulary activity is completed, then generate the next one only after the
current Vocabulary row is completed. The lesson must be fast, level-aware,
local-first, and cheap:

- one compact `openai/gpt-5.6-luna` text request;
- one structured vocabulary artifact (five words maximum, with meaning and a
  short example where needed);
- no background retry, prefetch, or lookahead generation;
- no Speaking row, or any other skill, may be created by this lane.

The generic harness already supplies the gate, one-row serial behavior,
`harness_skill=vocabulary`, local plan persistence, Supabase sync, and the
existing provider cost ledger.

## What exists today

Course already routes a vocabulary artifact to
`VocabularyFlashcardsScreen` through `SpeakCourseActivityScreen`. Course passes
`preparedContentOnly: true`, so the screen renders saved content and does not
ask the lesson agent to invent missing examples on mount.

`GeminiLiveAudioService` already provides the local/cloud cache contract:

- local app-support cache, keyed by a SHA-256 of version, voice, speed, and
  normalized text;
- private Supabase Storage bucket `vocabulary-audio`, path
  `userId/v1/<cache-key>.pcm`;
- `vocabulary_audio_cache` index row with text, voice, checksum, bytes, sample
  rate, channels, and encoding;
- lossless `gzip` storage (`pcm_s16le+gzip`), decoded back to original PCM16
  bytes before playback;
- local cache first, then remote download/restore after reinstall;
- an in-flight map that deduplicates the same explicit audio request.

The current audio generator is a one-shot exact-script renderer using
`models/gemini-3.1-flash-live-preview`. It is not the conversational tutor: it
reads an immutable French script exactly once and never explains or answers
it. Playback calls `loadCached`; a cache miss does not silently open Live.

## Required Vocabulary behavior

1. **Text generation** — Luna receives only the learner level, selected topic,
   a short learning snapshot, and the immediately previous Vocabulary
   lesson title/words. Do not send the entire course, full history, or old
   generated artifacts. Keep the prompt compact and force the existing JSON
   artifact shape.
2. **Persist first** — save the text artifact and row state before any optional
   audio work. A slow or missing clip must never discard a valid lesson.
3. **Audio policy** — do not loop over every word and sentence during Course
   row creation. The current repair loop can open one Live generation per clip
   and is the main Vocabulary cost/latency risk. The optimized path should
   use an already mirrored clip, or generate a clip only from an explicit
   learner action. Never generate audio merely because the card screen
   mounted.
4. **Tutor guidance** — keep one explicit Live connection for the current
   Vocabulary card when the learner taps the phone/tutor control. Send only
   the current word, meaning, current example (if present), learner level,
   and requested action (`pronounce`, `repeat`, or `grade`). Do not retain
   previous cards in the application context. Existing Live compression stays
   as a safety net, not as a substitute for small application messages.
5. **Checks** — preserve the existing fast local pronunciation matcher. Live
   is for optional guidance/feedback, not for every local record check. A
   cached speaker tap is zero Google calls; an explicit Live check is one
   bounded turn on the already-open socket.

## Cost target

The target is a single small Luna request per generated lesson and no Google
request on cached playback. The Vocabulary Live message should be a few
hundred tokens at most: current card plus action, not a 4K/12K transcript.
Track these events separately in the existing ledger:

- `course_prepare_requested` / provider result for Luna text;
- `audio_cache_hit_local` or `audio_cache_hit_remote`;
- explicit `audio_generation_requested` and `live_audio_generation` only when
  a clip is intentionally prepared;
- Live tutor connect/turn usage for guidance.

Do not claim a dollar estimate from code alone; provider usage metadata in the
ledger is the source of truth for the configured Google and OpenRouter
accounts.

## Development test sequence

1. Build Debug with the harness target `vocabulary`.
2. Complete Unit 2 Vocabulary. Confirm one queued Vocabulary row, one claim,
   one Luna response, and no retries.
3. Open the row. Confirm the artifact renders immediately from saved JSON.
4. Tap a cached speaker control and confirm a local/remote cache hit with no
   Live generation event. Clear only the local cache and repeat to verify the
   gzip decode/restore path from Supabase.
5. Tap the explicit tutor control. Confirm one Live socket, compact current-
   card context, and no previous-card context after Next.
6. Complete the row and repeat for three or four rows. Confirm the next row is
   Vocabulary, sequence increases by one, and all other personalized skills
   remain absent from this lane.
7. Run the focused Flutter tests and inspect the NDJSON ledger before enabling
   another skill.

## Implementation boundary

The first Vocabulary code change is limited to the generic harness selection,
Vocabulary gate, and tests/docs. Do not alter the already working Speaking
matcher, authored Unit 1/Unit 2 content, Supabase schema, or gzip cache
contract. Any change to the current per-clip audio repair loop should be a
separate, measured change after the text lane is verified.
