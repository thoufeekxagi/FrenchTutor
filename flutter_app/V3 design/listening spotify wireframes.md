# V3 Listening — Spotify-Inspired Wireframes

## Proposal status

Wireframes and generated artwork only. No Listening UI code changes are included.

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

## Artwork system

Every generated listening item receives two coordinated images from the same
content brief:

1. **World artwork** — a wide scene describing the broader story or song mood.
   It fills the Now Playing background and receives a dark readability gradient.
2. **Identity artwork** — a square character, narrator, or artist image. It is
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
- The transcript is not shown by default; the user opens it from the compact
  Transcript bar.
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

## Migration from the current implementation

```text
Current                                      Proposed
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

No implementation should begin until this proposal is approved.
