# ParleSprint — Pilot Execution Plan (P0 → P4)

**Branch:** `pilot` · **Created:** 2026-07-17 · **App:** `flutter_app/`
**Companion docs:** `PILOT_PLAN.md` (data-layer architecture), `orchestration_plan_v1.md` (adaptive engine)

This is the single source of truth for pilot readiness. Work top-to-bottom. A priority
tier is DONE only when every acceptance criterion in it passes — no half-done items
carried forward silently. When implementation deviates from this doc, update the doc
in the same commit.

**North-star for the pilot:** a learner can rely on one evidence-backed daily mission:
practice a practical French ability at the right level, speak it with a tutor, resume
exactly where they stopped, and see real evidence shape the next mission — without ever
hearing a language they did not ask for, hitting a dead session, or waiting on a spinner
long enough to wonder if the app froze.

---

## Ground rules (apply to every tier)

1. **English and French only — strict.** The tutor speaks and writes ONLY French and
   English and never ENGAGES with any other language (no translating, no acknowledging
   its content). Other-language speech is also OMITTED from the transcript display and
   session records (script-based client filter). Any native-language support is a
   post-pilot feature (P4.2) — not designed into the pilot at all.
1b. **Content policy is absolute (App Store readiness).** Family-friendly output always,
   in every session type: no profanity, slurs, or sexual/violent/hateful content, in any
   language. Offensive input is never repeated or engaged — the tutor stays calm and
   redirects to the lesson. Lives as one shared `contentSafety` block composed into every
   live prompt plus the text-brain guardrail.
2. **The app directs, the model performs.** Structure (cards, beats, stage transitions)
   is owned by Dart code; the model gets one instruction per turn. Never hand the model
   the whole script and hope.
3. **Every stage resumes.** Force-quit, crash, or disconnection at any moment must land
   the user back at the same stage with the same content (already the coordinator's
   contract — never regress it).
4. **No silent fallbacks that degrade content.** A failed generation shows a retry, it
   never substitutes stale lab content (the "same croissant forever" bug class).
5. **Local DB stays Supabase-shaped** (uuid PKs, user_id columns, ISO timestamps,
   soft deletes, forward-only migrations) so auth/cloud in P1 is a copy, not a rewrite.

---

## P0 — Pilot blockers (broken or trust-destroying) — CODE COMPLETE on this branch

> Status 2026-07-18: all P0 code is implemented and unit-tested. Every acceptance
> criterion below marked [x] is verified by tests/code inspection; the remaining [ ]
> items are on-device probes (wifi-kill, backgrounding, foreign-language probes,
> full daily-path run) that need a real phone build before P0 is declared DONE.

### P0.1 Language guardrail in every prompt

**Problem.** No prompt in the app constrains output language. `GeminiLiveService.systemPrompt`
says "bilingual" but nothing forbids replying in Spanish/Hindi/Malayalam if the student
speaks it. Users can be from anywhere; one wrong-language reply destroys trust.

**Change.**
- New file `flutter_app/lib/prompts/live_prompts.dart`: a `languageGuardrail` block that
  is composed into EVERY live system prompt, stating: understand any language; reply
  ONLY in French and English; if the student uses another language, acknowledge warmly
  in English and continue in French/English; never write or speak any other language
  even when directly asked, even for a single word or translation.
- Same guardrail constant appended to every user-facing text prompt in
  `lesson_agent_service.dart` (`askQuestion`, `checkDictation`, `quizFeedback`,
  `getWritingHint`, `gradeMicroWriting` comment, `gradeWriting` strings).
  (Invisible-JSON prompts — intent judge, planners, pronunciation audit — don't need it;
  their output is never shown or spoken.)

**Acceptance.**
- [x] A test asserts the guardrail + content-policy text is present in every `LivePrompts`
      variant and in the lesson-agent guardrail. (`test/live_prompts_test.dart`)
- [x] Non-Latin-script transcripts (Malayalam, Tamil, Hindi, Arabic, CJK, Cyrillic, …)
      are omitted from display/records/intent-judging in all four live screens.
      (`lib/utils/transcript_filter.dart`, `test/transcript_filter_test.dart`)
- [ ] Manual probe: speak/type Spanish and Malayalam to Marie in free talk and to the
      lesson Q&A; every reply is French/English only and the foreign lines never appear
      in the transcript.
- [ ] Manual probe: say something rude mid-session; Marie stays calm, never repeats it,
      redirects to the lesson.

### P0.2 Per-session-type system prompts

**Problem.** One generic prompt serves five very different session types; the only
differentiation is a context blob appended at the end. Structured stages fight the
freeform-tutor instructions (e.g. "ask one follow-up question at a time" contradicts
"say exactly this line and nothing else").

**Change.**
- `LiveSessionType` enum: `freeTalk`, `speakingRoleplay`, `vocabStage`,
  `listeningScene`, `grammarStage`.
- `LivePrompts.forSession(type)` composes: persona base (Marie, warm, short replies,
  no markdown, profile-calibrated) + language guardrail + a role block specific to the
  session type. The listening scene's ACTOR-COACH rules move from the screen's context
  blob into its role block; free talk keeps today's behavior.
- `GeminiLiveService` takes `sessionType` (default `freeTalk`) and builds its system
  prompt from `LivePrompts`; `lessonContext` remains the per-day content payload.
- All four call sites pass their type (session_screen, agent_led_vocab, agent_led_listening,
  agent_led_grammar).

**Acceptance.**
- [x] Each screen constructs the service with its own type; a test pins the role-block
      markers per type (e.g. roleplay prompt contains role-lock rules, vocab prompt
      contains card-discipline rules).
- [ ] No behavioral regression in vocab/listening choreography (manual run of each stage).

### P0.3 Roleplay role-lock (speaking stage correctness)

**Problem (user-reported).** In the closing roleplay the tutor doesn't play the opposite
character properly and doesn't respond/reply correctly. Root cause: the speaking stage
gets the generic tutor prompt + one context line "have a short natural conversation" —
no character, no scenario, no rule to stay in role or to always answer the student's
last line.

**Change.**
- `speakingRoleplay` prompt: Marie picks ONE concrete everyday scenario from today's
  material and plays the OTHER role (vendor/clerk/friend). Hard rules: open in character
  by naming the scene in one English sentence then starting in French; ALWAYS respond
  directly to what the student just said before anything else; stay in character; drop
  to English coaching ONLY when the student is stuck or asks; then return to the scene;
  one short turn at a time.
- `PathwayCoordinator._speakingContext()` upgraded: pass today's vocabulary, grammar
  focus, and the listening scene's scenario title so the roleplay CONTINUES today's
  world instead of inventing an unrelated one.
- Kickoff injection in `SessionScreen` becomes stage-aware (roleplay kickoff = "open the
  scene now" instead of the generic "greet and ask what they want to practice").

**Acceptance.**
- [ ] Manual: run the full daily path; in the speaking stage the tutor opens a scene tied
      to today's words, answers each student line in character, and coaches only when asked.
- [ ] The tutor never narrates plans ("I will now...") and never breaks the scene without
      being asked.

### P0.4 Call lifecycle — reconnect, backgrounding, timeouts

**Problem.** Any WebSocket drop = session over ("Connection lost"). No
`WidgetsBindingObserver` anywhere: backgrounding the app or taking a phone call leaves
audio/socket state undefined. `connect()` that never completes hangs on "Connecting…"
forever.

**Change (service-level, so ALL live screens inherit it).**
- `GeminiLiveService`:
  - Connect timeout (10s to setupComplete → error).
  - Auto-reconnect on unintentional disconnect: up to 3 attempts, 1s/2s/4s backoff,
    with Gemini Live `sessionResumption` handles (request in setup, store
    `sessionResumptionUpdate` handles, pass handle on reconnect so the conversation
    continues; fresh session + silent context note as fallback).
  - Handle server `goAway` by proactively reconnecting.
  - New callbacks: `onReconnecting(attempt)`, `onReconnected`; `onDisconnected` now fires
    only when reconnection is exhausted or the disconnect was intentional.
- ALL live screens (`SessionScreen` + the three agent-led stages): `WidgetsBindingObserver`
  — on pause, stop mic streaming; on resume, restart mic (unless deliberately muted) and
  let the service reconnect if the socket died in the background. New
  `CallStatus.reconnecting` UI state on every live screen.
- Agent-led screens additionally RE-ANCHOR the session on reconnect: vocab/grammar
  re-announce the current card, listening re-directs the current beat/phase (or replays
  the finale beat) — so even a fresh no-handle session knows exactly where it was.
- `SessionScreen` on final disconnect auto-ends the call: transcript saved, result
  screen shown — never a dead call UI.
- Cancel/mid-call exits, resume, and honest completion thresholds already exist in the
  coordinator — verified, not rebuilt.

**Acceptance.**
- [ ] Kill wifi mid-call for <15s: call shows "Reconnecting…", then continues with context intact.
- [ ] Background the app 30s mid-call, return: call continues (or reconnects), no zombie audio.
- [ ] Airplane-mode before dialing: clear error within 10s, not an infinite spinner.
- [ ] Every existing resume/retake path still works (force-quit mid-stage → same stage/content).

### P0.5 Speed — kill the biggest wait

**Problem.** Opening the listening stage blocks on a Flash-Lite scene generation (1–3s
good case, 25s timeout worst case) even though the input (today's words) is known the
moment vocab ends.

**Change.**
- Pre-generate the scene fire-and-forget in `PathwayCoordinator` immediately after the
  vocab stage completes; persist to `session.readingPassageJson`. Opening listening then
  reads the persisted scene instantly. Inline generation stays as the fallback (vocab
  skipped, pre-gen failed).
- Guard against double-generation (in-flight flag; never overwrite an existing script).

**Acceptance.**
- [ ] Vocab → listening within the same sitting opens the scene with no blocking dialog.
- [ ] Vocab skipped: old inline path still works with the spinner.

**Out of P0, explicitly:** per-stage retake UI (P1.6), transcript-derived summaries (P1.4),
voice speed (P2). Session *resume* is P0 and already held by the coordinator.

---

## P1 — Must exist before strangers get builds

### P1.1 Minimal auth — CODE COMPLETE (2026-07-18)
Supabase project live (`oxfnrsjskdjbroekxdco`, ca-central-1). Native Apple + Google +
email/password, no browser redirect ever (signInWithIdToken flow, not the web OAuth
flow — that was the root cause of the earlier "app kicks you out to a browser" bug).
- [x] `profiles` table + RLS (select/update own row only, no client insert policy) +
  auto-provisioning trigger on `auth.users` insert (security definer, revoked from
  anon/authenticated RPC access) + `updated_at` trigger. Verified with `get_advisors`.
- [x] `AuthService` (native Google/Apple/email, graceful "not configured" for Google
  until its external setup is done, every native-cancel path treated as silence not
  error) + `AuthScreen` (Passeport-styled, official Apple button, custom Google
  button, forgot-password) + `AuthGate` (session → onboarded → home routing,
  replacing the old always-local onboarding check).
- [x] Local DB: migration v7 adds `referred_by_code` (nullable, future-proofing for
  promo codes — no redemption logic yet) + `LearningStore.linkSupabaseUser()` stamps
  `user_id` on every sign-in (idempotent, skips soft-deleted rows).
- [x] iOS native: `Runner.entitlements` (Sign in with Apple) wired into all 3 build
  configs; Info.plist has the Google URL-scheme slot ready (placeholder until the
  external Google Cloud step). Verified with a full `flutter build ios --release`.
- [x] Settings: sign-out row (with confirm dialog) — no dead end.
- [ ] External, one-time, human-only steps (Google Cloud OAuth clients, Supabase
  dashboard provider toggles, one Xcode capability click) — see
  `AUTH_SETUP_CHECKLIST.md`. Apple + email sign-in already work with zero further
  setup; only Google is gated on this.

### P1.2 Free hour + rate limits
- Append-only `usage_events` table (already Supabase-shaped): one row per live-call
  minute and per text-brain call.
- Wallet: 60 free voice minutes per account; hard stop with a friendly paywall-shaped
  screen (pilot: "you've used your free hour — tell us what you thought" + contact).
- Per-minute meter visible in Settings. Server-side enforcement comes with Supabase
  (RLS + edge function); pilot enforcement is client-side but written against the
  same usage_events data.

### P1.3 Live mic modes + noise-safe navigation — CODE COMPLETE (2026-07-18)
- [x] **Auto mode** (hands-free, server VAD — today's behavior) and **Hold / push-to-talk
  mode** (mic streams ONLY while the hold button is pressed; on release a 3s silent-PCM
  tail closes the utterance for server VAD). Noise physically cannot become an utterance
  in Hold mode.
- [x] One shared `MicController` (`lib/services/mic_mode.dart`, fully unit-tested) +
  `MicModeBar` widget (compact Auto/Hold pill; wide hold button only in Hold mode) wired
  into ALL FOUR live screens. Mode persists app-wide; switchable mid-call; mute exists
  only in Auto (Hold already gates the mic); backgrounding-safe in both modes.
- [x] **Noise rule for Auto mode**: when the LLM intent judge fails/times out, NOTHING
  navigates (the old keyword fallback used to scan garbled noise for "next"/"oui" and
  move the card — that path is dead). Cards move only on a confident judge verdict or a
  button tap.
- [ ] On-device probe: noisy environment (bus/street audio) in Auto → card never moves
  without a clear command; Hold mode → speech only registers while held.

### P1.3b Daily fallback content overhaul (still open)
- The LLM-driven Daily path is the product; the static fallback becomes a decent
  correct session (never mixed lab leftovers).

### P1.4 Post-session summary + word practice
From the saved transcript + evidence rows: most-practiced words, hardest pronunciations
(pronunciation-audit tags already collected), one "practice these tomorrow" list.
Rendered on the daily review screen; feeds SRS priorities.

### P1.5 Auto-suggest with zero data
Suggestion surfaces must produce sensible level-based defaults when history is empty
(first-run = everyone's first impression). Audit every consumer of evidence/history for
empty-state behavior.

### P1.6 Retake UX
Retake an individual stage or the whole day (soft-delete today's row and recreate —
migration v6 already unblocked this). Confirmation dialog; evidence rows are never
deleted, a retake is a new session.

---

## P2 — Differentiators — CODE COMPLETE (2026-07-18)

### P2.1 Four personas (2M/2F, France + Québec) — DONE
- [x] `lib/models/tutor_persona.dart`: Marie (France, F, Aoede), Julien (France, M,
  Puck), Camille (Québec, F, Leda), Mathieu (Québec, M, Orus). Persona = display
  identity + Gemini voice + accent/register prompt block (Québec blocks teach real QC
  expressions, glossed in English, TEF-Canada framed).
- [x] `ActiveTutor` app-wide holder (loaded at startup, sync-readable, listenable);
  unknown/legacy ids fall back to Marie. A call CAPTURES its persona at dial time —
  identity/voice never change mid-call, even across reconnects.
- [x] Live calls and the TTS line-replay voice both follow the persona; all live-screen
  labels (header, avatar initial, "X is speaking", hint texts) are persona-dynamic.
- [ ] On-device probe: each persona sounds distinct; Québec personas actually use QC
  register; persona survives app restart.

### P2.2 Onboarding — DONE, upgraded to v2 (2026-07-18)
- [x] New "Who will you practice with?" step (page 3 of 4): both accents explained,
  four tutors with taglines; choice saved via ActiveTutor; final page references the
  chosen tutor by name.
- [x] **v2 — CEFR levels:** the level question is now A1/A2/B1/B2 with plain-English
  descriptions, stored in the profile. `LearnerLevel` helper maps BOTH the CEFR and
  legacy ('zero'/'basics'/'conversational') vocabularies everywhere — old installs
  need no migration and can never crash on level reads.
- [x] **v2 — tutor voice previews:** every tutor card has a ▶ button playing a 3–4
  sentence sample in that tutor's REAL voice (Gemini TTS with per-persona voice
  override; `TutorVoicePreviewer` — cached per screen, toggle to stop, quiet failure
  offline, lazy audio so picker screens stay audio-free until first play). Same
  preview buttons in the Settings persona grid.
- [x] **v2 — one question removed:** English/French mix is DERIVED from level
  (A1/A2→gentle, B1→balanced, B2→immersion) at onboarding finish, adjustable anytime
  in Settings. Only questions that feed course-building remain: goal, CEFR level,
  session length, tutor.
- [ ] On-device probe: all four previews play in distinct voices; onboarding
  completes and the daily plan respects the chosen level.

### P2.3 Tutor tuning in Settings — DONE
- [x] "Your tutor" card: 2×2 persona grid (accent-labeled), English/French mix
  (Gentle/Balanced/Immersion) and speaking pace (Slower/Natural/Faster) pills.
  Mix/pace are prompt lines composed into every live prompt, explicitly subordinate
  to stage-specific language rules; garbage stored values fall back to defaults.
  Applies from the next call (stated in the UI).

### P2.4 One-step voice navigation polish — VERIFIED, no changes needed
Edge cases confirmed present in all three stage screens: goto is range-guarded and
same-index-guarded, navigation has a 1.5s cooldown after any card move, advance/back
walk exactly one step (learn↔play phases in the scene), bare-consent "yes" only
honored after the practice threshold, and (P1.3) judge failure navigates nowhere.

---

## P3 — Complete the surface

### P3.1 Pronunciation tab
New tab fed by pronunciation-audit tags + P1.4 summaries: hardest sounds, per-word replay
(cached TTS), drill list. Absent today; data already accumulates.

### P3.2 Writing fully integrated
Writing stage graduates from bolt-on: hints ladder, evidence, summary contributions, and
entry from the dashboard all coherent.

### P3.3 TCF/TEF mock speaking test + scoring (first post-pilot feature)
1–2 mock tests mirroring the real exam structure (TEF Canada Expression Orale sections
A/B; TCF speaking tasks 1–3), timed, scored from the transcript against the official
rubric dimensions with CLB-mapped feedback. Monetization anchor. Post-pilot but designed
now: sessions must store enough transcript/timing metadata (they do).

---

## P4 — After the pilot proves out

### P4.1 Obsidian-style orchestration graph
Interactive competency-graph view (nodes = competencies, edges = prerequisites, glow =
recent evidence). Retention garnish; zero learning-loop risk.

### P4.2 Native-language bridge (Malayalam, Tamil, …)
French tutoring scaffolded through the learner's mother tongue for users without strong
English. Requires: per-profile `support_language`, guardrail extension ("French +
English + {support_language}"), persona prompts per bridge language, and its own
verification pass. Ships as its own phase with its own guardrail design — never as a
quiet exception to P0.1.

---

## File map (P0 touchpoints)

| File | P0 role |
|---|---|
| `flutter_app/lib/prompts/live_prompts.dart` (new) | Guardrail + persona base + per-type role blocks |
| `flutter_app/lib/services/gemini_live_service.dart` | sessionType, reconnect, resumption, timeouts, goAway |
| `flutter_app/lib/services/lesson_agent_service.dart` | Guardrail on user-facing text prompts |
| `flutter_app/lib/screens/session/session_screen.dart` | Lifecycle observer, reconnecting UI, stage-aware kickoff |
| `flutter_app/lib/flow/pathway_coordinator.dart` | Roleplay context upgrade, scene pre-generation |
| `flutter_app/lib/screens/pathway/agent_led_*.dart` | Pass sessionType; inherit reconnect |
| `flutter_app/test/live_prompts_test.dart` (new) | Guardrail + role-block pinning tests |
