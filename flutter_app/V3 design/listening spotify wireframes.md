# V3 Listening — Spotify-Inspired Wireframes

## Proposal status

The Spotify-inspired Listening redesign is now implemented in the Flutter
app. This document remains the wireframe and interaction contract; the
implementation notes below record what shipped so the design does not drift.

## Implementation status — 2026-08-20 (player correction pass)

### Shipped listening shell

- The session opens as an immersive player, not a six-step exercise card.
- The persistent top bar now matches the Reading shell: Back, “Mark as
  listened”/“Listened”, Settings, and More. The More menu stays at the top in
  the normal player, transcript view, Quiz, Keywords, and Grammar.
- The player uses “Lyrics”, “Quiz”, “Keywords”, and “Grammar”. The old “Story”
  label is gone from Listening because the audio itself is the main story
  surface. The learning rail is hidden in the normal player and appears only
  when a learning destination is open.
- Lyrics is an optional full-screen player state. The globe control opens it;
  the chevron closes it. The same globe toggles English translation beneath
  every visible French line. Lyrics sit directly over the artwork with a black
  readability gradient, not inside a bright card.
- The normal player keeps the compact identity artwork, title, format,
  favorite, metadata, translation, text-size, copy, and playback controls
  together above the progress bar.
- Quiz, Keywords, and Grammar hide transcript/translation automatically and
  use a compact mini-player so their content has room to breathe.

### Artwork and persistence

- “cover_url” remains the compact 4:3 identity artwork used by cards and the
  player metadata row.
- Every generated listening lesson independently generates a true 9:16 portrait
  backdrop. The source prompt explicitly ignores compact-cover, 4:3, square,
  landscape, and crop instructions, and the backdrop is stored in the existing
  “music_background_url” field for backward-compatible persistence.
- Compact identity covers remain a separate 4:3 image. Full-screen listening
  backdrops use a separate `-listening` Storage object and a larger image budget
  (160 KB, with a bounded 240 KB retry); compact cards retain the 25 KB target.
- The Supabase “generated_stories.music_background_url” column and the local
  migration are part of the shipped data contract.

### Intentional control mapping

The center utility action is Copy French because the app does not carry a
native share dependency. It is functional and keeps the dependency surface
unchanged. A native share sheet can replace it later without changing the
player layout.

The design keeps FrenchTutor's learning value but changes the hierarchy:

```text
Audio story / song
      ↓
Immersive Now Playing
      ↓
Optional transcript + translation
      ↓
Check · Words · Grammar
```

## Rendering contract — production path

- GPT-5.6 Luna is the single canonical lesson writer for text listening
  packages. It returns structured JSON calibrated to A1, A2, B1, or B2; the
  exact French lines and English meanings are persisted before audio is made.
  Gemini is not chained into listening generation and is not a playback
  fallback.
- ElevenLabs is the renderer, not the author of lesson meaning. Story
  narration uses Eleven v3 with renderer-only performance direction and
  deliberately slow delivery; educational audio uses multilingual v2 with a
  slower instructional setting; podcast audio uses Eleven v3 dialogue with
  eight alternating, tagged host/guest turns.
- Music uses a structured multi-section `music_v1` composition plan because
  that is the plan shape supported by the detailed endpoint. It gives the
  song verse/refrain/outro structure, extra room for lyrics, filters unsafe or
  copyrighted style references, retries a rejected composition plan with a
  conservative style set, and sends the audio to Scribe before accepting it.
- Every returned audio clip includes a validation record. A clip is not
  accepted into a lesson unless it has non-empty MP3 bytes and its rendered
  words match the canonical French script. The native player speed control is
  separate from provider pacing.
- The player speed setting is separate from provider rendering and is applied
  to the native player at 0.75×, 1×, or 1.25×. The progress bar follows native
  playback position/duration, not just the selected sentence.

## Artwork system

Every generated listening item receives two coordinated images from the same
content brief:

1. **World artwork** — a true 9:16 portrait scene describing the broader story
   or song mood. It fills the Now Playing background and receives a dark
   readability gradient.
2. **Identity artwork** — a compact character, narrator, or artist image. It is
   used in the compact metadata row, library cards, queue, and notifications.

For **The Garden Key**:

- World artwork: `assets/images/listening/the_garden_key_background.png`
- Identity artwork: `assets/images/listening/the_garden_key_character.png`

For stories, the identity artwork represents the narrator or central character.
For songs, it can represent the fictional artist or performer.

## 1. Listening library

Purpose: make the library feel like an audio service, not an exercise index.

```text
┌──────────────────────────────────────┐
│ Listening                         ⚙   │
│                                      │
│ Continue listening                   │
│ ┌──────────────────────────────────┐ │
│ │       WORLD ARTWORK              │ │
│ │                                  │ │
│ │  The Garden Key                 │ │
│ │  A1 · French story · 3 min      │ │
│ │  ────────────────  62%          │ │
│ │                       ▶ Continue│ │
│ └──────────────────────────────────┘ │
│                                      │
│ Made for your French                │
│ [Daily stories] [Slow narration]    │
│ [French songs]                      │
│                                      │
│ Recent listening                    │
│ ┌──────────────────────────────────┐ │
│ │ [small art] The Garden Key    ›  │ │
│ │             A1 · 3 min           │ │
│ ├──────────────────────────────────┤ │
│ │ [small art] A Walk by the Sea ›  │ │
│ │             A2 · 4 min           │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

## 2. Primary Now Playing screen

Purpose: the main Listening experience. The user hears the story immediately;
transcript and exercises are available without blocking playback.

```text
┌──────────────────────────────────────┐
│  ˅             The Garden Key     ⋯  │
│                                      │
│                                      │
│          WORLD ARTWORK               │
│      full-bleed garden scene         │
│      dark gradient at bottom         │
│                                      │
│                                      │
│  ┌─────┐                             │
│  │ art │  The Garden Key             │
│  └─────┘  Narrated by Camille        │
│           A1 · French story          │
│                              ♡       │
│                                      │
│  ─────────●──────────────────────    │
│  0:42                         -2:18  │
│                                      │
│       ↶      ◀       ▶       ▶      │
│                         1×           │
│                                      │
│  ┌──────────────────────────────────┐ │
│  │  ▣  Transcript              ↗   │ │
│  └──────────────────────────────────┘ │
│                                      │
│  [ Check ]    [ Words ]    [Grammar] │
└──────────────────────────────────────┘
```

### Decisions

- The world artwork is the visual anchor, like Spotify's Now Playing artwork.
- The small identity artwork is repeated beside the title and narrator.
- Lyrics are not shown by default; the user opens them from the globe control
  or the top overflow menu.
- `Check`, `Words`, and `Grammar` are secondary learning destinations, not a
  forced six-step progression.
- The top-right overflow is the home for secondary actions and settings.

## 3. Transcript / lyrics mode

Purpose: reveal the French transcript as an immersive, synchronized layer.

```text
┌──────────────────────────────────────┐
│  ˅             The Garden Key     ⋯  │
│                                      │
│  The boy searches through the garden │
│                                      │
│  Le garçon cherche sa clé.           │
│                                      │
│  Il regarde sous le vieux banc.      │
│  He looks under the old bench.       │
│                                      │
│  Le jardin est silencieux ce soir.   │
│  The garden is quiet tonight.        │
│                                      │
│  ─────────●──────────────────────    │
│  0:42                         -2:18  │
│                                      │
│       ↶      ◀       ❚❚      ▶      │
│                                      │
│  [FR / EN]   [Aa]   [🔊]   [⋯]      │
└──────────────────────────────────────┘
```

### Learning behavior

- The currently spoken sentence is brighter and larger.
- The current word receives the existing gold highlight/underline behavior.
- English translation is independently toggleable.
- Tapping a French word opens the existing meaning/conjugation model.
- Sentence and word timing remain required for reliable synchronization.

## 4. Learning destinations

The player remains the parent experience. These open as tabs or sheets from the
Now Playing screen:

```text
┌──────────────────────────────────────┐
│ ‹  The Garden Key              ⋯     │
│                                      │
│  Listen      Check      Words Grammar│
│  ──────                              │
│                                      │
│  Words from this story               │
│                                      │
│  doucement                 gently  🔊│
│  jardin                    garden  🔊│
│  attendre                  to wait 🔊│
│                                      │
│  Tap a word for meaning, context,    │
│  save, audio, or conjugation.        │
│                                      │
│  ┌──────────────────────────────────┐ │
│  │  ▶  Continue listening           │ │
│  └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

`Check` contains comprehension and optional dictation. `Grammar` contains the
existing conjugation and explanation surfaces. Shadowing should remain a
Speaking activity rather than a primary Listening destination.

## 5. Settings sheet

Purpose: preserve the shared Reading settings model and add Listening-specific
controls without creating a second settings architecture.

```text
┌──────────────────────────────────────┐
│ Listening settings               Done│
│                                      │
│ Show transcript                 OFF  │
│ Show translation                OFF  │
│ Highlight spoken words          ON   │
│ Underline words                 ON   │
│ Auto-play word audio            OFF  │
│                                      │
│ Text size       Small  Medium  Large│
│ Playback speed  0.75×   1×    1.25× │
│                                      │
│ Mark as learned                       │
│ Call tutor                            │
└──────────────────────────────────────┘
```

## Migration record

```text
Before                                       Implemented
──────────────────────────────────────      ─────────────────────────────────
Listen / Check / Focus / Dictate /           Now Playing is the main screen
Shadow / Done                                

Done opens StoryReaderScreen                 Transcript is a player state

Transcript hidden until a stage gate         Transcript hidden by preference;
                                             reveal from player

Focus owns vocabulary                        Words becomes a first-class tab

Dictate is a required stage                  Dictate becomes optional in Check

Shadow is inside Listening                   Shadow moves toward Speaking

Settings sheet already exists                Extend shared Reading settings
```

## Acceptance checklist for the proposal

- The first screen feels like an audio player, not a quiz flow.
- The wide artwork and compact identity artwork have visibly different jobs.
- Transcript is discoverable but not forced on first open.
- French, English, word meaning, translation, and playback speed remain easy to
  access.
- Existing audio, quiz, vocabulary, grammar, persistence, and tutor behavior can
  be preserved behind the redesign.
- The UI works in dark mode, respects safe areas, and keeps controls tappable.

## Open question

The wireframe uses “Narrated by Camille” as placeholder metadata. Decide later
whether that row should name the tutor voice, an AI-generated narrator, or the
story character.

This proposal is approved and the Listening player implementation is now the
source of truth for future visual changes.
