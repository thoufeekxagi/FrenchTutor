# V3 Listening Redesign — Wireframes and Implementation Record

## Scope

The original wireframe proposal has now been implemented and this file is the
historical contract plus the current behavior record. The listening UI keeps
the existing lesson/audio data flow while presenting it as an immersive player.

The existing Flutter implementation has two listening surfaces:

1. **Listening library/home** — `ListeningLabScreen`
2. **Listening session** — `ListeningPracticeScreen`

The session still has six internal learning stages:

```text
First listen → Quick check → Focus → Dictation → Shadowing → Recap
```

The redesign keeps that learning order because listening must be heard before
the transcript is revealed. It borrows the approved story language: dark
canvas, gold accent, English-only story titles, image-only artwork, compact
rounded stage rail, no global bottom navigation inside the session, and a
small centered audio island.

The visible Listening shell now presents those stages through the player and
the four learning destinations Lyrics, Quiz, Keywords, and Grammar. The
internal stage state remains available for comprehension, dictation, shadowing,
and recap.

## Production generation path — 2026-08-20

Listening uses one canonical writer and one audio renderer. GPT-5.6 Luna writes
the A1/A2/B1/B2 lesson package as structured JSON. ElevenLabs then renders the
selected format from the frozen French lines: expressive Eleven v3 for story
narration and podcast dialogue, slower multilingual v2 for education, and a
sectioned music composition plan for songs. No provider is used as a silent
playback fallback. Audio is accepted only after MP3 validation and transcript
validation; music also passes an Eleven Scribe check and retries a rejected
composition plan with safe styles.

## Implemented contract — 2026-08-20 (player correction pass)

### Shared Reading-style shell

- Full-bleed artwork occupies the session background.
- The top bar is persistent across the normal player, transcript overlay, and
  learning destinations: Back, “Mark as listened”/“Listened”, Settings, and
  More.
- More is a top-level action, not a duplicate inside the lower playback rail.
- The settings sheet remains the shared place for playback, translation,
  text-size, and listening preferences.

### Spotify-style player behavior

- Normal state: compact identity artwork, title, format, metadata, favorite,
  globe/lyrics control, text-size, copy, playback rail, and actual elapsed
  progress. The reading-style four-tab island is not shown in this state.
- Lyrics state: the full-screen artwork remains visible under a black
  gradient; French lines are large and left-aligned, the active line is
  emphasized, and English translation appears directly beneath each visible
  French line when enabled.
- Learning state: Quiz, Keywords, and Grammar automatically close transcript
  mode and use a mini-player at the bottom.
- The audio source remains ElevenLabs-rendered content; the canonical lesson
  text and segment translations remain the learning source of truth.

### Artwork contract

- Compact story artwork: 4:3 cover for library rows and metadata.
- Listening player artwork: independent 9:16 portrait generation for every
  audio format, persisted as generated_stories.music_background_url for the
  current schema. The compact cover and full-screen background are never the
  same generated object.
- Full-screen backdrops use 768×1365 dimensions with a 160 KB target and
  bounded 240 KB retry. Compact covers continue to use the 25 KB target.
- Playback subscribes to Flutter Sound's real position/duration stream,
  supports pause/resume, applies 0.75×/1×/1.25× playback speed, and derives the
  active line from elapsed audio rather than only from button taps.
- If the portrait is not ready yet, the player safely uses the compact cover
  until the saved story refreshes.

## 1. Listening library/home

Purpose: choose a topic, generate a new listening story, resume the latest one,
or reopen an earlier story.

```text
┌──────────────────────────────────────┐
│ Listening                       ⚙    │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │  🎧  Create a listening lesson  › │ │
│ │      A fresh audio story at A1   │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [Surprise me] [Travel] [Food]  →     │
│                                      │
│ CONTINUE LISTENING                   │
│ ┌──────────────────────────────────┐ │
│ │        image-only 4:3 artwork    │ │
│ │                                  │ │
│ │  CONTINUE                        │ │
│ │  The Lost Object                 │ │
│ │  A1  ·  7 scenes  ·  3 min       │ │
│ │                         ▶ Listen  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Previous listening                   │
│ ┌──────────────────────────────────┐ │
│ │ [thumbnail]  The Golden Hour   › │ │
│ │              A1  ·  3 min        │ │
│ └──────────────────────────────────┘ │
│ ┌──────────────────────────────────┐ │
│ │ [thumbnail]  A Walk by the Sea › │ │
│ │              A2  ·  4 min        │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

Implementation mapping:

- Keep `ListeningLabScreen` generation, topic selection, local story loading,
  cover prewarming, and route opening.
- Rename the visual sections from “Your short books” to “Previous listening”.
- Keep generated titles in English; the French stays inside the lesson.
- Use full-width horizontal previous-story rows rather than a dense card grid.
- The current global app navigation can remain outside this route; the focused
  lesson itself hides it.

## 2. First listen — stage 01

Purpose: audio first. The transcript is intentionally hidden until the story
has completed once.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object          ✓ Learned│
│                         ⚙             │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │                                  │ │
│ │       image-only artwork         │ │
│ │       dark top/bottom gradient    │ │
│ │                                  │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ Catch the meaning first.             │
│ A1 · 3 min · transcript hidden      │
│                                      │
│ Listen for who, where, and what      │
│ changes. One clean listen is enough. │
│                                      │
│             ┌──────────────┐         │
│             │ ▶  1×  ↻     │         │
│             └──────────────┘         │
│             Line 1 of 7              │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ 🎧  Replay is available after    │ │
│ │     the first complete listen.  │ │
│ └──────────────────────────────────┘ │
│                                      │
│       [ Check what I caught ]       │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_firstListenView` and `_AudioPlayerCard`.
- Preserve `_hasListened` gating on the primary action.
- The audio island owns play/pause, stop, speed, and replay; it should be
  content-width and centered, never full-width.
- Keep `Mark as learned` and settings in the hero header, without the global
  bottom navigation.

## 3. Quick check — stage 02

Purpose: verify global comprehension before revealing the French transcript.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object          ✓ Learned│
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ What stayed with you?                │
│ Question 1 of 2                      │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Why does the character return?   │ │
│ │                                  │ │
│ │ ○  To find a missing key         │ │
│ │ ○  To meet a friend              │ │
│ │ ○  To buy a ticket               │ │
│ └──────────────────────────────────┘ │
│                                      │
│             [ Next question ]       │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_checkView` and `_ChoiceButton` with gold selected/correct states.
- Keep the existing question count, bilingual question support, answer
  tracking, and transition to Focus.
- The rail is navigational progress, not a free jump that bypasses the
  first-listen rule. Before completion, later stages remain visually quiet.

## 4. Focus / transcript — stage 03

Purpose: reveal one line at a time, replay it, optionally translate it, and
inspect a word without turning the screen into a dense card stack.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object          ✓ Learned│
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ Tune your ear                 2 / 7  │
│ Hear it. See it. Replay it.          │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ LINE 02                          │ │
│ │                                  │ │
│ │ Le garçon cherche sa clé.        │ │
│ │ The boy looks for his key.       │ │
│ │                                  │ │
│ │          ↻ Replay   0.75×   文A  │ │
│ └──────────────────────────────────┘ │
│                                      │
│       ‹ Previous       Next ›        │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ cherche                          │ │
│ │ to look for                      │ │
│ │ Conjugate →                      │ │
│ └──────────────────────────────────┘ │
│                                      │
│          [ Next line ]               │
│                  ┌──────────────┐   │
│                  │ ▶  ■ 0.75× ↻ │   │
│                  └──────────────┘   │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_focusView` as the listening equivalent of the approved story
  reading surface.
- Keep word taps, keyword lookup, line navigation, replay, speed, and optional
  translation. Use the same contextual word-meaning and conjugation behavior
  as the story reader, rather than inventing a second meaning model.
- Use a French/English translation icon, not a generic eye-only control.
- Keep the selected word meaning compact and neutral; conjugation opens the
  same neutral grammar sheet used by the story reader.

## 5. Dictation — stage 04

Purpose: convert listening into precise recognition of one missing French word.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object                  │
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ Can your ear fill the gap?           │
│ Active listening · Dictation         │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Replay the line                  │ │
│ │                                  │ │
│ │ Le garçon cherche sa _____.      │ │
│ │                                  │ │
│ │            ▶  0.75×              │ │
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Type the missing French word     │ │
│ │ [                              ] │ │
│ └──────────────────────────────────┘ │
│                                      │
│             [ Check answer ]         │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_dictationView` while preserving the existing target-selection,
  normalization, scoring, recorder, and transition to Shadowing.
- Use the same playback island pattern; it should not become a large fixed
  footer.
- Correct/incorrect feedback should be inline and short, with the gold accent
  reserved for the next action.

## 6. Shadowing — stage 05

Purpose: listen, repeat the complete line, and receive a clear pronunciation
signal without making the learner feel examined.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object                  │
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ Borrow the rhythm.                   │
│ Optional voice check                 │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Le garçon cherche sa clé.        │ │
│ │ The boy looks for his key.       │ │
│ │                                  │ │
│ │          ▶  Play target line     │ │
│ │                                  │ │
│ │          🎙  Record attempt      │ │
│ └──────────────────────────────────┘ │
│                                      │
│ I heard: “...”                       │
│ Good match. Your version is clear.   │
│                                      │
│          [ See listening recap ]     │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_shadowView` and keep the existing speech-recognition lifecycle,
  transcript, Gemini judgment, and rough-match fallback.
- Show recording state with a restrained gold waveform/status treatment, not a
  large animated card.

## 7. Listening recap — stage 06

Purpose: close the session with evidence and one next action.

```text
┌──────────────────────────────────────┐
│ ‹   The Lost Object                  │
│                                      │
│ [ Listen ] [ Check ] [ Focus ]       │
│ [ Dictate ] [ Shadow ] [ Done ]      │
│                                      │
│ Your ear did the work.               │
│ Listening recap                      │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │              2 / 2               │ │
│ │          details caught          │ │
│ │  ✓ Dictation landed              │ │
│ │  ✓ Shadowing completed           │ │
│ └──────────────────────────────────┘ │
│                                      │
│ Keep the phrases that were hard.     │
│ They are the best next lesson.       │
│                                      │
│          [ Finish listening ]        │
│                                      │
│          Open full transcript        │
└──────────────────────────────────────┘
```

Implementation mapping:

- Restyle `_recapView` and preserve score calculation, session recording, and
  Transcript remains a player destination instead of forcing a route change to
  `StoryReaderScreen`.
- The primary button closes the listening session; the transcript link remains
  secondary.

## Shared listening settings sheet

There is no dedicated listening settings screen today. The proposal is to use
the same shared session sheet as Story Reader, with listening-specific controls
added only where they are meaningful:

```text
┌──────────────────────────────────────┐
│ Listening settings                 × │
│                                      │
│ Text size                 Small •••  │
│ Playback speed            0.75× •••  │
│ Show translations              ◉     │
│ Highlight words                 ◉     │
│ Underline words                ◉     │
│ Auto-play word audio            ○     │
│ Dark mode                      ◉     │
└──────────────────────────────────────┘
```

The existing listening settings sheet now supplies this shared behavior. The
top-bar Settings action stays available in both normal and transcript states.

## Implemented design rules

- Listening is not a second reading homepage. Its library is a listening
  library, and its session is an immersive audio-first player over the
  existing six internal stages.
- No global bottom navigation inside the focused session.
- No title or text embedded in generated artwork.
- English story titles only; French appears in the transcript and exercises.
- Use the existing story-reader gold, dark canvas, neutral surfaces, and
  Spotify-like player dock with a compact mini-player for learning tabs.
- Keep all existing behavior: audio prewarm, pause/resume/stop, replay, speed,
  quiz scoring, dictation checking, recording, pronunciation judgment, session
  recording, cover refresh, notetaker, and transcript handoff.

## Historical approval gate

These wireframes were approved and implemented in this order:

1. Listening library/home
2. First listen
3. Quick check
4. Focus
5. Dictation
6. Shadowing
7. Recap and shared settings

Future UI changes should update the implementation record and preserve the
shared Reading-style shell, persistent top-bar actions, and translation
overlay behavior.
