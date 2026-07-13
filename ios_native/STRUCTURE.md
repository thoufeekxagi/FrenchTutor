# Agent-led lesson stages — what we learned building Vocab, to reuse for Reading/Listening

This documents the architecture that came out of a lot of trial and error on the Daily
Pathway's vocab stage (`AgentLedVocabView.swift`). Vocab is now the reference
implementation. Reading & Listening (`AgentLedListeningView.swift`) is still on the OLD
pattern (model decides navigation via tool calls) — rebuild it against the rules below
instead of patching it piecemeal.

## The one-sentence version

**Gemini Live teaches. It never decides state.** Every "what happens next" decision —
advance, go back, show the next question — is made by deterministic app code watching
the student's own words (or a button tap), never by a model tool call.

## Why: what we tried that didn't work

- **Model calls `next_card`/`show_question` on its own judgment.** Looked reasonable, broke
  constantly: it would decide to advance after a single weak attempt, or narrate as if it
  had moved on without ever calling the tool (leaving the screen stuck while it talked past
  the actual state), or fire the same tool call twice in a row (Google-documented Gemini
  Live behavior — dedupe by call ID if you keep any model-driven tool at all).
- **A "gate" that verifies the model's tool call before honoring it** (require an attempt,
  require explicit intent) was a real improvement over trusting it blindly, but it was still
  reactive — waiting to see what the model proposes, then judging it. Any delay in that
  loop (we had a 5-second watchdog before defaulting to the app's own decision) is felt by
  the student as "why is this thing ignoring me."
- **Live-generating content mid-session** (example sentences, question text) via the model
  was a second, separate source of failure: batches truncate unpredictably (reasoning
  models burn part of the output budget on hidden reasoning before the visible JSON even
  starts), so content silently went missing. This has nothing to do with pacing and should
  never be solved by tuning the live call — see the content rule below.
- **"Match your pace, use your judgment" pacing instructions** read by the model as license
  to rush. A beginner needs an explicit, ordered, numbered script it must follow every
  single time, not a vibe.
- **System-prompt instructions fade over a long session.** Rules stated once at connect time
  visibly degraded in adherence after ~5-6 turns. Fix: re-state the load-bearing rules in
  every context note sent at each state transition, not just at the start.

## The pattern (do this for every agent-led stage)

### 1. App owns state, model has zero navigation tools

- All progression (current word/question/passage index) lives in `@State` in the SwiftUI
  view, mutated only by app code — never as a side effect of a model tool call.
- Detect the student's explicit intent from their own transcript (`onUserTranscript`, never
  the model's own output transcript) with a plain keyword matcher — see
  `detectIntent(_:)` in `AgentLedVocabView.swift`. No LLM call needed for this.
- The moment intent is detected, execute the transition **immediately**, synchronously, in
  the same function. No delay, no waiting to see what the model does first.
- Always add an explicit on-screen "Back" / "Next" (or equivalent) button next to voice
  control, wired to the exact same transition functions. This is a zero-dependency
  fallback: it works even if the student's phrasing doesn't match a keyword, on a fresh
  install, with no tuning. Voice and button call the same code path — never two.
- The model keeps at most one tool for pure in-the-moment judgment that doesn't affect
  navigation (e.g. `mark_result` grading pronunciation quality). If a stage has nothing
  like that, it can have zero tools.
- After every transition, tell the model what changed via `injectContext(...)` — a plain
  text note, not a tool response — so it can react in natural conversation. It doesn't
  decide, it's informed.

### 2. Content is pre-generated once, offline — never live

- Anything the model would otherwise "make up" during the session (example sentences,
  comprehension questions, passage scripts) gets generated **once**, offline, before
  shipping, and bundled as a static JSON file the app looks up synchronously at runtime.
- Vocab's version: `Content/vocab_examples.json`, keyed by word id, `{fr, en}` per entry,
  loaded via `ContentService.vocabExamples(for:)`. Zero LLM calls, zero latency, zero
  failure risk at session time.
- Generation script pattern (see `generate_vocab_examples.py`, ask for it if rebuilding):
  - Small batches (~8 items) — large batches truncate silently on reasoning models.
  - Concurrent requests (thread pool), not sequential — this alone cut generation time by
    ~5-8x with no quality cost.
  - Checkpoint results to disk after every batch, so a kill/crash never loses progress.
  - Multi-pass convergence: a batch that comes back partial just requeues its missing
    items into the next pass, instead of retrying the whole batch and hoping.
  - A strict "keep the exact word/tense form given, don't conjugate/inflect it" instruction
    mattered a lot for vocab — the equivalent for reading/listening is probably "keep the
    passage at the stated CLB level, don't drift into advanced grammar."

### 3. Beginner-appropriate teaching script, stated as an explicit numbered sequence

- Don't write "teach naturally, use your judgment" — write an ordered list of steps the
  model must follow every time, e.g. (vocab's actual current version):
  1. Say the target content + English meaning together.
  2. Ask the student to respond/repeat, give them room to actually try.
  3. React briefly.
  4. Walk through supporting content (example sentence / passage detail) already on screen.
  5. Only now ask if they're ready to move on — and wait for the real answer.
- State a minimum number of repetitions/passes for new/unfamiliar content (we landed on
  4-5 passes for a brand-new vocab word, 2 for a familiar one) — err toward more practice,
  a true beginner is not being served by speed.
- Say explicitly which language is the explaining language. Our students don't speak
  French yet: all of the model's own explaining/encouraging/asking must be in English;
  French appears only as the literal target content (the word, the passage, the sentence),
  never as the model's own explanatory language. State this as its own CRITICAL rule, not
  folded into something else — it's easy for a model to drift out of on its own.
- Re-state the pacing + language rules (condensed) inside every `injectContext(...)` call
  at a state transition, not just once in the system prompt — this is what actually keeps
  the model on-script deep into a long session.

### 4. Debug visibility from day one

- A live on-screen panel (see `debugPanel`/`logDebug(_:)` in `AgentLedVocabView.swift`)
  logging every detected intent and every state transition with a reason, timestamped,
  auto-scrolling — build this into a new stage immediately, not after the fact. It's what
  made all of the above bugs actually diagnosable instead of "it feels wrong somehow."

## Applying this to Reading & Listening specifically

`AgentLedListeningView.swift` currently gives the model `show_conjugation`, `ask_drill`,
`grade_drill`, `show_question`, `mark_answer` as tools it calls on its own initiative
(`AgentTool.listeningPalette` in `AgentTool.swift`) — this is the exact pre-vocab-fix
pattern and should be expected to have the same pacing/desync problems.

Concrete rebuild checklist:
- [ ] Passage text and comprehension questions (with answer choices) for every listening
      exercise get pre-authored offline into the content JSON (`Content/listening.json` —
      check what's already there before generating anything new), not built live.
- [ ] `show_question`/`ask_drill` stop being model-called tools. The app advances through
      a fixed, pre-loaded list of questions/drills for the current exercise, driven by the
      same detected-intent-or-button pattern as vocab's next/back.
- [ ] `grade_drill`/`mark_answer` can stay as model tools (judgment calls: was the spoken
      answer correct), same role as vocab's `mark_result` — but make sure they're gated so
      they only apply to the question the app currently has active, and dedupe by call ID.
- [ ] `show_conjugation` is a good candidate to become static screen content tied to the
      current grammar point (shown automatically when that point comes up), rather than a
      tool the model decides to fire.
- [ ] Add the same debug panel + `logDebug` pattern.
- [ ] Write the system prompt with an explicit numbered per-passage/per-question script
      (play/present → question → answer → feedback → only then ask to advance), the same
      English-primary rule, and the same "re-state rules in every context note" habit.
