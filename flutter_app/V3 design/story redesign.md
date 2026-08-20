# V3 Story Reader Redesign

## Status

Implemented the approved Readle-inspired story-reader pass on the canonical
Flutter app. This is a compile/test-verified implementation pass; visual QA on
the target iPhone still needs to be done by running the Flutter app locally.

## Screen contract

The story reader is an immersive full-screen session. It keeps story-specific controls but removes the global app navigation.

## Artwork contract

- Generated story artwork is image-only: no embedded title, words, letters, numbers, labels, logos, captions, or UI.
- Artwork requests now pass an explicit aspect ratio to the MiniMax Edge
  Function. The default story/card contract is landscape 4:3.
- MiniMax requests allow one visible character and instruct the model to keep
  the subject inside the central safe area. The provider boundary no longer
  requests a portrait title cover.
- The storage boundary still normalizes saved card artwork to 4:3. Reader hero
  work therefore uses a safe-center composition until a separate 16:9 hero URL
  is introduced.
- The shared visual direction is grounded cinematic realism with subtle editorial stylization: believable materials, natural light, restrained grading, and one clear focal scene.
- Story titles are rendered by Flutter outside the artwork as English UI text.

### Top controls

- Back
- Mark as learned
- Story settings
- Tutor call and report actions remain available over the hero image.

### Internal stage rail

```text
Story — Quiz — Keywords — Grammar
```

The rail is a compact rounded island. The current stage uses the gold accent; inactive stages remain quiet charcoal/gray.

### Reading surface

- A full-width, approximately 246 logical-pixel hero band sits directly above
  the stage island.
- A dark top-to-bottom gradient keeps white controls and selected-word text
  legible without embedding text into the generated image.
- The English story heading, level, read time, translation toggle, text settings, like, and report actions sit below the stage island.
- Bilingual French/English content flows below the heading without sentence
  cards. Translation on creates spaced bilingual sections; translation off
  keeps the French content in a continuous reading flow.
- Gold is reserved for the accent/action state. The selected word itself is
  white over the hero gradient.
- A selected glossary word is surfaced at the lower-left edge of the hero with
  its English meaning. A `Conjugate →` action appears only when the segment's
  grammar note identifies a verb/tense cue and opens an on-demand grammar call.
  Every source word is tappable. It receives an immediate positional glossary
  fallback and is then refined by a contextual Gemini response using the word,
  French sentence, English sentence, and learner level. The selected word and
  meaning are shown in the hero overlay; no gold outline is used around the
  conjugation sheet.
- The visible Full story / Sentences switch and sentence-mode setting are
  removed from this reader. Translation is the source of truth for the reading
  presentation.

### Audio island

The old full-width bottom toolbar was replaced with a smaller centered translucent island
whose width is driven by its contents, containing:

- Play / pause
- Stop
- Playback speed
- Replay sentence
- Words

Story content receives bottom inset so the island never hides text.

## Shared session settings

Added `SessionSettings` as a shared persisted source of truth for focused practice sessions:

- Small / medium / large text size.
- Playback speed.
- Translate sentences.
- Highlight selected and spoken words.
- Underline words.
- Auto-play word audio.
- Dark/light reading mode.

The translation icon beside the English heading is a quick shortcut for the persisted
`Translate sentences` preference.

The first reader text icon is a French/English translation toggle. The second
text-size icon cycles the reading scale upward; the settings sheet remains the
source of truth for choosing a smaller size. The heart is backed by a local
user-scoped `story_favorites` table and synchronizes to Supabase when the learner
is signed in. The duplicate hero report action is removed; the metadata row keeps
the single report action.

The reader consumes these settings now. Other practice screens and the global settings screen should consume the same service in a later pass.

## Preserved behavior

- Segment-level audio selection: tapping a paragraph chooses where playback
  begins, while the visual reading surface remains one continuous flow.
- Narration, pause, resume, stop, speed, and sentence replay.
- Word selection and translation matching.
- Contextual word meaning fallback for every tapped French word.
- Per-user story favorites, with local persistence and sign-in hydration.
- Tutor call context and lifecycle handling.
- Notes overlay.
- Session recording.
- Keyword audio.
- Grammar explanation and conjugation data.
- Quiz answer tracking and scoring.
- Enrichment updates while a story is open.

## Known follow-up work

1. Finish dark/gold treatment for every Grammar, Quiz, and Keywords subcomponent.
2. Move the shared settings UI into the app-wide Settings screen.
3. Apply the shared dark/light setting to all practice shells.
4. Add screenshot-based visual checks at 375×812, 393×852, and 430×932.
5. Introduce a separate 16:9 `readerHeroUrl` if visual QA shows the 4:3 card
  artwork still crops important subjects in the immersive reader.
6. Migrate the remaining legacy story surfaces to use the English-only heading helper.

## Verification

- `flutter analyze --no-pub`: no errors; only the project’s existing
  info-level lints remain.
- The previously completed full suite passed all 272 existing tests.
- `flutter test test/story_favorite_store_test.dart`: passed the new
  story-favorite regression test. A subsequent full-suite rerun was blocked
  before test discovery when the local Flutter SDK tried to rewrite its engine
  cache outside the workspace; this is an environment permission issue, not a
  test failure.
- `flutter build ios --no-codesign`: completed successfully from the canonical
  `flutter_app` directory.
- No emulator or physical device was launched.
