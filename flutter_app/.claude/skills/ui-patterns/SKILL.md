---
name: ui-patterns
description: Navigation, component, and interaction patterns for making this Flutter app feel like a native Apple app (not a ported Android/Material app) and for keeping the product's non-gamified, serious-learner tone. Use whenever building a new screen, adding navigation, choosing a dialog/picker/switch widget, or reviewing existing screens for native-feel or gamification regressions.
---

# UI patterns — navigation, components, flows

Full rationale lives in [`design.md`](../../../design.md) at the project root. This skill is the
"how to build a screen" checklist. Pair with the `design-system` skill for tokens (color, type,
spacing, motion).

## Current state (know this before touching a screen)

Audit finding: **this app currently uses zero Cupertino widgets.** Every screen is built from
`MaterialPageRoute`, `ElevatedButton`, `BottomNavigationBar`, `ListTile`, and Material `Icons.*`
inside a `MaterialApp`. This is *the* reason the app doesn't feel native yet, despite having a
distinctive, well-designed color/type system already (`Passeport`). When you touch any screen,
prefer migrating its widgets to the Cupertino/adaptive equivalents below rather than leaving it
as-is — don't let native and non-native screens accumulate side by side longer than necessary.

## Navigation

- **Push/pop (drilling into content):** use `CupertinoPageRoute`, not `MaterialPageRoute`. This
  is what gives the edge swipe-to-pop back gesture — one of the most-felt native cues, and it
  silently breaks with Material routes or ad hoc `PageRouteBuilder`s. If introducing a shared
  navigation helper, make `CupertinoPageRoute` the only path so this can't regress per-callsite.
- **Tab bar:** top-level sections only (Home, Labs, Progress, History, Settings — 5 tabs, at the
  upper edge of Apple's recommended 3–5; don't add a 6th). Use `CupertinoTabScaffold`/
  `CupertinoTabBar` or a Material `BottomNavigationBar` styled to match — but never nest a second
  tab bar inside a tab.
- **Sheets:** use for focused, dismissible tasks (starting a practice session, quick settings
  edit) — `showCupertinoModalPopup` / `showModalBottomSheet` with a drag handle, not a full push.
- **Action sheets vs alerts:** `CupertinoActionSheet` for a set of mutually exclusive choices
  (e.g. "export as / share as"); `CupertinoAlertDialog` for a single yes/no or informational
  decision. Don't use Material `AlertDialog` — visually and animationally distinct from iOS.

## Components

Swap these Material defaults for their Cupertino/adaptive counterparts wherever a screen is
touched:

| Instead of | Use |
|---|---|
| `MaterialPageRoute` | `CupertinoPageRoute` |
| `AlertDialog` | `CupertinoAlertDialog` |
| Material date/time picker | `CupertinoDatePicker` |
| `Switch` | `Switch.adaptive` or `CupertinoSwitch` |
| `Icons.*` | `CupertinoIcons.*` |
| `ListTile` + `Material` ink wrapper | a plain tappable row (`GestureDetector`/`CupertinoListTile`) with **no ripple** — iOS has no ripple idiom at all |
| `Card`/`Material` elevation shadows | `BackdropFilter` blur + translucent surface for anything meant to read as "layered" (nav bars, sheets) |
| Custom bouncy easing (`Curves.elasticOut`) | `Curves.easeOutCubic` or low-bounce spring (see `design-system` skill) |

Existing widgets to reuse rather than reinvent: `PasseportCard` (bordered surface),
`PasseportPrimaryButton` (primary CTA) — both in `lib/widgets/`. If either still uses
Material-only styling internally (e.g. `ElevatedButton`, `Material` wrapper for the tap
highlight), that's a good target to migrate rather than working around it.

## Screen flow conventions

- **Empty states:** describe what will appear and why, in the existing serif/body type — no
  mascot illustration, no "no worries!" cutesy copy. Treat it like a reference tool, not a game.
- **Progress/completion:** show real numbers (sessions, words learned, accuracy) in
  `Passeport.mono` — never a flame/streak icon, never a leaderboard rank, never a badge-unlock
  animation. If marking a genuine milestone, a quiet fade/scale is the ceiling for celebration —
  no confetti, no full-screen animation.
- **Notifications/reminders:** if the app ever sends push copy, it should read like a calm
  reminder ("Your next session is ready"), never guilt-framed or voiced by a character.
- **Lesson/session screens:** take structural cues from Babbel (clear, classroom-like sequencing)
  and Busuu (fast, minimal-chrome navigation between exercise types) — but keep zero gamification
  chrome from either.

## Review checklist (use when reviewing or refactoring any screen)

1. Does this screen use `CupertinoPageRoute` (not `MaterialPageRoute`) to get here and to push
   further? Does the edge-swipe-back gesture work?
2. Any Material ripple visible on tap (`InkWell`/`ListTile`/`Material` splash)? Remove it.
3. Any `Icons.*` that should be `CupertinoIcons.*`?
4. Any dialog/picker/switch that's Material instead of Cupertino/adaptive?
5. Any scroll view that clamps instead of bounces at its edges?
6. Any animation curve that overshoots more than a subtle, low-bounce settle?
7. Any streak flame, mascot, badge-unlock, confetti, or leaderboard chrome? Remove — this product
   doesn't do gamification chrome, by deliberate positioning (see `design.md` §1).
8. Are all tap targets ≥44×44pt?
