# V3 Story Reader Redesign

## Status

Implemented first visual pass on the canonical Flutter app.

## Screen contract

The story reader is an immersive full-screen session. It keeps story-specific controls but removes the global app navigation.

### Top controls

- Back
- Story title
- Tutor call
- Report problem
- Story settings

### Internal stage rail

```text
Read — Words — Grammar — Quiz — Done
```

The rail is a compact rounded island. The current stage uses the gold accent; inactive stages remain quiet charcoal/gray.

### Reading surface

- Full-width cover artwork with a dark gradient into the reading canvas.
- Story title and level/time metadata over the lower part of the cover.
- Bilingual French/English content below.
- Gold word selection and playback highlighting.
- Selected glossary word is surfaced in the cover area as a small meaning cue.

### Audio island

The old full-width bottom toolbar was replaced with a smaller centered translucent island containing:

- Play / pause
- Playback speed
- Replay sentence
- Next stage

Story content receives bottom inset so the island never hides text.

## Shared session settings

Added `SessionSettings` as a shared persisted source of truth for focused practice sessions:

- Small / medium / large text size.
- Playback speed.
- Translate sentences.
- Underline words.
- Auto-play word audio.
- Dark/light reading mode.

The reader consumes these settings now. Other practice screens and the global settings screen should consume the same service in a later pass.

## Preserved behavior

- Sentence-by-sentence and full-story modes.
- Narration, pause, resume, stop, speed, and sentence replay.
- Word selection and translation matching.
- Tutor call context and lifecycle handling.
- Notes overlay.
- Session recording.
- Keyword audio.
- Grammar explanation and conjugation data.
- Quiz answer tracking and scoring.
- Enrichment updates while a story is open.

## Known follow-up work

1. Finish dark/gold treatment for every Grammar, Quiz, and Keywords subcomponent.
2. Add richer optional vocabulary metadata: part of speech, gender, CEFR band, infinitive, and conjugation.
3. Move the shared settings UI into the app-wide Settings screen.
4. Apply the shared dark/light setting to all practice shells.
5. Add screenshot-based visual checks at 375×812, 393×852, and 430×932.

## Verification

- Targeted Flutter analysis passes with no issues.
- No emulator or physical device was launched.
