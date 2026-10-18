# V3 UI structure

Audience: adults preparing for TCF Canada, starting from zero. They pay, so
every screen must answer: what do I do now, why, how long, how far from the
goal. Premium means restraint and clarity, not decoration.

Evidence this is needed (measured on the real app): the current Home carries a
stock-photo hero, three quick-start tiles, a streak card, a course list and
explore chips, with a "Photo tutor" tab. Nothing mentions TCF, NCLC or an exam
date.

## Visual language

- Light by default (warm off-white canvas, near-black text), dark mode later.
- One accent for primary actions, one success green. Retire black and gold.
- One typeface (Inter), hierarchy from size, weight and spacing.
- Few cards, only to group or to act. 4pt spacing, 16pt surfaces, 12pt controls.
- Motion 200 to 350ms ease-out. No confetti, XP, coins, lives, leagues.
- Retheme by changing `DesignTokens` and `app_theme.dart` once. Screens never
  hardcode colors or spacing.

## Screen contract (write before building any screen)

```
Screen: <name>   Key prefix: <prefix>.
User arrived to...
They must understand...
Primary action...          (exactly one)
Secondary action...
Success state...
Must not contain...
States: default, loading, empty, error, interrupted, completed
```

Put the contract as a comment at the top of the screen file.

## Screens

| Screen | Intent | Pattern source |
|---|---|---|
| Onboarding | animated greeting, three concise TCF value screens, optional exam date, single-row level choices, optional reminders, consent/account gates, then optional Marie practice | Babbel greeting/value slides; single-column choice rows |
| Learn home | Bonjour greeting, level and exam date, weekly activity, a vivid course continuation, four compact practice actions, and the TCF path | approved home reference, 2026-10-18 |
| Daily challenge | one short, authored TCF-style task sequence, one step at a time, clear feedback and a useful next step | Speak practice, Babbel review |
| Path | stage and unit list with states, what each unit lets you do | Babbel course list |
| Lesson player | one instruction per step, big answers, bottom feedback bar, Previous beside Continue, Marie phone button and inline panel | Speak lesson skeleton |
| Marie | practise this lesson, exam examiner, ask anything, correction cards | Speak roleplay and corrections |
| Mocks | timed sections and full mocks, results with per-skill level and fix plan | new |
| Progress | per-skill estimated level vs target, weak topics, countdown | Babbel profile |
| Paywall | total price dominant, trial timeline, Restore, Terms, Privacy | Vocabulary.com trial timeline |

Reference screenshots live in `references/extracted/` (local only, not in git).

## Lesson step types (one shared player)

word, phrase repeat, grammar card, multiple choice, listen once (TCF style),
arrange the sentence, speak and compare. Every French string has a speaker
button (it asks the tutor to say it). Every step has the Marie phone button.

## Approved Learn home contract

The approved home reference is the screen with `Bonjour!`, the A1 and exam
date chips, a Monday-to-Sunday activity strip, the illustrated course card,
the two-by-two practice grid, and the illustrated TCF path card. The bottom
navigation remains Learn, Marie, Tests, and Me. There is no Course/Practice
segment on this screen; the practice tiles open their destinations directly.

```text
Screen: Learn home   Key prefix: learn.
User arrived to: open the app and choose one useful French action.
They must understand: what lesson to continue, what practice is available,
their real weekly activity, and where the full TCF path lives.
Primary action: continue the authored course lesson. Exactly one.
Secondary action: daily challenge, Marie, review words, Stories, and TCF path.
Success state: each action opens its existing route and real progress remains
available when the learner returns home.
Must not contain: invented streaks, fake challenge availability, XP, coins,
lives, or a second competing primary action.
States: default, loading, empty, error, interrupted, completed.
```

## Daily challenge screen contracts

These are the design contracts for the daily-challenge wireframes in
`docs/v3/daily-challenges/`. Challenge content and learner completion are not
yet connected to a published Supabase feed.

```text
Screen: Daily challenge   Key prefix: dailyChallenge.
User arrived to: start or resume the challenge tile from the Learn home.
They must understand: the current skill, step count, progress, and the response
they are being asked to make.
Primary action: answer or continue the current step. Exactly one.
Secondary action: exit and resume later; open the selected tutor when a speaking
step needs it.
Success state: objective results are shown with explanations and the Learn
home reflects the real completion state.
Must not contain: invented scores, XP, coins, lives, leaderboards, guilt copy,
or unreleased answer keys in a public content table.
States: default, loading, empty, error, interrupted, completed.
```

## Rules for building v3 UI

1. Read `lib/design/tokens.dart`, the nearest existing screen and the
   primitives in `lib/widgets/` first. Extend a primitive rather than clone it.
2. Targets at least 44x44pt, text scaling to 200% without clipping, one
   Semantics label per control placed on the control itself.
3. Every interactive widget: `ValueKey('<screen>.<element>')` plus a label.
   `tool/check.sh` enforces it in `lib/v3`.
4. No fake data, progress, scores or AI feedback. Empty states say what is
   missing.
5. Verify by probe and screenshot at default and large text, then update
   `docs/v3/SCREEN_MAP.md` with `python3 tool/screen_map.py`.
6. Copy: short adult language, no em dashes in user-facing text, no guilt
   copy, no "AI" claims the data does not support.
