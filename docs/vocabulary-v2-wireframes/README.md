# Vocabulary V2 — wireframe and interaction proposal

Status: proposal only. No application code is changed by this document.

## Product direction

Vocabulary should feel like a short, personal practice session rather than a
large library of unrelated cards. The home screen answers “what should I do
now?” in one glance, then offers a small amount of exploration underneath.

## Home information architecture

1. **Continue review** — the highest-value due queue, with an honest count and
   a short estimated session length.
2. **Build a set** — use today’s mission context, choose a theme, or generate a
   set with Marie.
3. **Explore sets** — image-led, compact two-column cards with level, word
   count, and learning status.

The persistent bottom navigation stays on the home screen. Inside a session it
is removed so the learner has one job and one clear exit.

## Session contract

The six lesson stages remain, but the navigation becomes one compact line:

`Preview · Learn · Recall · Context · Use · Done`

The active stage is gold, completed stages are quiet gold, and future stages
are muted. There is no second row of labels beneath a progress rail. The lesson
header keeps back, title, item count, and overflow on one line as well.

### Card rhythm

- **Preview:** see the small set and the shared situation.
- **Learn:** image + French word + pronunciation + one useful sentence.
- **Recall:** retrieve the word before revealing the answer.
- **Context:** choose the word that makes the sentence work.
- **Use:** write or say one short sentence, with optional AI feedback.
- **Done:** show what is ready, what needs another pass, and when the next
  review is due.

## Personalisation and content logic

Each card is built from a frozen content packet before the learner sees it:
canonical word, CEFR level, image prompt/result, pronunciation, three to seven
context variants, stable audio keys, and source provenance.

Sources are combined in this order:

1. words due in spaced review;
2. the current daily mission and its passage/scene;
3. recent speaking, listening, reading, and writing sessions;
4. learner-selected theme or a Marie-generated theme.

The same word may recur across different contexts, but each recurrence has a
different job: recognition, listening, retrieval, choice, production, or
transfer. This makes repetition meaningful instead of showing the same card
seven times.

## SRS behavior to preserve and clarify

- Quick / Standard / Deep sessions target about 3 / 5 / 8–10 total items.
- Due reviews are first; new words are capped by session length.
- A failed or uncertain word can re-enter the current session immediately.
- Unaided correct = **Got it**; correct with a hint = **Almost**; wrong or
  skipped = **Again**.
- The learner sees the next review window after grading, without exposing
  opaque scheduler internals.
- Leaving mid-session saves the exact stage and card so Continue reopens it.

## AI generation guardrails

“Generate with Marie” creates a small set from the learner’s current level,
goal, recent errors, and mission context. Images, examples, and audio are
prepared together, validated for duplicates and level fit, then cached. If
generation is unavailable, the app falls back to existing curated content and
does not block practice.

## Visual decisions

- Preserve the existing dark charcoal + warm gold identity.
- Keep imagery on set cards and on the learn card, but reduce decorative chrome.
- Use one primary action per screen; secondary tools become quiet icon buttons.
- Hide the floating notetaker from the home and summary surfaces; expose Marie
  from the session header when needed.
- Use consistent 44pt touch targets, restrained borders, and clear semantic
  states for ready / building / revisit.

## Screens in the attached overview

1. Vocabulary home
2. Choose or generate a set
3. Learn card
4. Recall card
5. Context / use card
6. Done / review summary

