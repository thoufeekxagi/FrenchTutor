# PCM audio deck implementation plan

## Goal

All newly generated Reading and Listening lessons use one sentence-level PCM
audio deck. The deck is generated once, persisted locally, mirrored to the
learner's private Supabase audio cache, and replayed through
`LessonSpeechService` so sentence and word highlighting share the same
playback callbacks. Course and Practice resolve the same deck contract.

## Runtime sequence

1. The LLM creates the immutable bilingual passage. Reading and Listening save
   that story immediately with a stable lesson id.
2. The app creates/opens the `lesson_audio_decks` SQLite manifest (migration
   V41) and prepares at most two sentence workers at a time.
3. Each worker checks the local PCM file first, then the private Supabase
   object. Only a true miss opens Gemini Live. The exact PCM bytes are written
   to Application Support and mirrored to `vocabulary-audio` plus its
   `vocabulary_audio_cache` index.
4. The manifest records the sentence text, voice, cache key, and local-ready
   state. A failed cloud mirror never causes a second Gemini render; a later
   preparation retries only the upload/index operation.
5. Playback queues the same sentence cache through `LessonSpeechService`.
   `onItemStart` selects the sentence and `onWordBoundary` drives the existing
   Reading-style word highlight. Listening no longer maps whole-track audio
   percentage to a guessed global word index.
6. Course Listening artifacts now carry a `pcm_deck_v1` marker instead of a
   full WAV. Course Reading, Listening, and Vocabulary prepare their missing
   audio only inside the explicit Generate action (including the single
   Generate-next action after a completed lesson); merely opening Course or a
   lesson never prepares audio.

## Completed in this change

- Add a local SQLite manifest for lesson audio-deck entries.
- Add one idempotent deck-preparation service with in-flight deduplication.
- Generate only missing sentence clips; never regenerate an existing local
  clip when cloud upload or metadata sync fails.
- Persist each generated clip through the existing Gemini local/Supabase PCM
  cache and record its cache key in the manifest.
- Route new Reading and Listening generation through the deck preparation
  before opening the lesson.
- Remove Listening's whole-track percentage-based word guessing and use the
  Reading-style `LessonSpeechService` sentence queue and word callbacks.
- Stop ordinary lesson opening/library warm-up from rendering a complete
  Listening WAV for new deck-based lessons.
- Add an explicit course-generation hook so a newly generated Course lesson
  uses the same deck service before later playback. This hook is not attached
  to Course entry, app resume, or lesson opening.
- Reserve a dark, fixed meaning/conjugation shelf above the Listening
  transcript so the story never overlaps the selected-word panel.
- Remove the old full-track prefetch/cache services and the course full-WAV
  upload path.

## Verification

1. Format modified Dart files.
2. Run the focused deck and Gemini audio tests.
3. Run `flutter analyze` on the app (pre-existing lint/info output is allowed;
   no new compile errors are allowed).
4. Run `git diff --check`.
5. Confirm the new lesson path writes a local manifest row and repeated opens
   hit local PCM without another Gemini call. Confirm idle Course/app screens
   do not invoke a provider and that leaving a Live lesson closes its socket.

## Follow-up hardening

- Add a Supabase migration for a first-class lesson-audio manifest if the
  existing `vocabulary_audio_cache` index is insufficient for account-wide
  restore inspection.
- Add a repair UI for a deliberately deleted local/cloud asset. Repair should
  target only the missing sentence and must never regenerate a complete lesson.
- Add device integration coverage for reinstall/hydration and cache-source
  telemetry.
