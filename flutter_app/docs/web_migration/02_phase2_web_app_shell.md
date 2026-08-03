# Phase 2: Web App Shell (Desktop Navigation & Layout)

**Status**: Implemented and visually verified.

**Decision recorded (important)**: ElevenLabs UI / shadcn are **React-only** and cannot run in Flutter — there
is no Flutter port and no way to embed React components in a widget tree. The founder chose to keep the single
Flutter codebase and *imitate* the reference's design language in hand-written Flutter instead of splitting
into a second React codebase. So: borrow the reference's **structure and density**, never its palette; every
colour and type value still comes from `DesignTokens`.

Built:

- `lib/widgets/web/web_app_shell.dart` — `WebAppShell` (sidebar + top bar), `NavDestination` (shared
  destination model), `WebIconButton`. Activates at `DesignTokens.breakpointExpanded` (1024px). Sidebar has a
  gradient brand mark, a quiet spaced-caps group label, and nav rows with hover + active states; the top bar
  carries the current section title plus an actions slot (currently a real Settings button).
- `lib/widgets/web/web_layout.dart` — the reusable web layout vocabulary: `WebPage` (scrollable, max-width
  1120, centred), `WebPageHeader`, `WebSectionHeader` (+ optional "View all" action), `WebTextAction`,
  `WebCard` (hairline border, hover tint/shadow), `WebCardGrid` (responsive columns, **equal tile heights per
  row** — a `Wrap` leaves card bottoms ragged, which is the most obvious "not designed" tell in a card grid),
  `WebChip`.
- `main_tab_screen.dart` now holds one `_destinations` list and one `_currentIndex` shared by both the mobile
  bottom tab bar and the desktop sidebar. Nothing is duplicated per platform.
- `onboarding_screen.dart` centres as a fixed 480px card on wide viewports instead of stretching full-bleed.
- `lib/dev/web_preview.dart` — **dev-only separate entrypoint** (`flutter run -d chrome -t
  lib/dev/web_preview.dart`) that renders the shell and every primitive against representative content. It
  exists because the real shell only appears after sign-in, which makes design iteration slow and impossible
  to verify without credentials. Doubles as the living style reference for `widgets/web/`.

Verified: `flutter analyze` clean; `flutter test` 192/193 (the one failure is the known pre-existing
`widget_test.dart` funnel test, unrelated); `test/web_app_shell_smoke_test.dart` covers render + tab switching;
and a real browser pass at 1440×900 confirmed layout, uniform card rows, working sidebar navigation (active
pill + top bar title update) and hover affordances.

Still NOT built, deliberately — see open decisions below: the top-bar global search (would be dead UI until
search exists), a richer desktop-only dashboard distinct from mobile's, a tablet-width intermediate layout,
and migrating the individual screens' internals to use `WebPage`/`WebCard` (the shell wraps them today, but
each screen's own body is still its mobile layout).

## The problem this phase solves

A web app is not a phone screen stretched into a browser tab. Right now `lib/screens/main_tab_screen.dart` is
a bottom-tab shell — correct for a phone, wrong for a desktop browser window. The reference the founder
pointed at (ElevenLabs' dashboard: a persistent left icon rail for primary navigation, a top bar with global
search, a wide content canvas with card/grid layouts) is the standard shape for a polished desktop web app —
Linear, Notion, and Slack all use this same pattern. That's the bar for "looks amazing, efficient" here, not
a mobile UI with wider margins.

## What changes and what doesn't

- **Changes**: the navigation *shell* — what wraps screen content and how the user moves between sections.
  On mobile: bottom tab bar (unchanged, exactly as today). On wide web viewports: a persistent left sidebar
  (icon + label per section — Home/Dashboard, Labs, History, Notes, Settings, etc., mirroring today's mobile
  tabs conceptually) plus a top bar (search, account menu, notifications).
- **Doesn't change**: the screens themselves. Grammar lab, writing lab, story reader, flashcard session,
  onboarding, settings content, etc. are pure Flutter widgets today (confirmed in the Phase 1 audit) and stay
  exactly as they are — they get placed inside whichever shell is active, not duplicated or rewritten.

This is the same "platform seam, not a fork" rule the rest of this plan follows, applied to navigation chrome
instead of a plugin: one `AppShell` concept, two visual implementations picked by viewport width, same screens
underneath either one.

## Recommended approach

1. Add a breakpoint decision (e.g. `LayoutBuilder`/`MediaQuery.sizeOf` — a constant like "≥900px wide = desktop
   shell" is a reasonable starting breakpoint; adjust after visual testing) at the top-level router/shell
   widget that currently always builds the bottom-tab `main_tab_screen.dart` layout.
2. Build a new `DesktopAppShell` (or similar) widget: persistent left sidebar (`NavigationRail` or a custom
   sidebar matching the design system, not stock Material) + top bar, with a content area that swaps between
   the same destination widgets `main_tab_screen.dart` already routes between.
3. Reuse the existing navigation *state* (whatever currently tracks "which tab is selected") for both shells —
   don't build parallel routing logic for desktop vs. mobile. Only the chrome differs.
4. Design polish pass: apply the existing design system (`.claude/skills/design-system`,
   `lib/theme/palettes.dart`'s `ProSystemAzure`) to the new shell — sidebar colors, icons, hover/active states,
   spacing — so it reads as one coherent product with the mobile app, not a different app wearing the same
   name. Reference screenshot inspiration (ElevenLabs-style layout) for structure and information density;
   never copy another product's literal color palette (same rule as the Readle reference used for mobile UX).
5. Onboarding on web: the founder specifically flagged this — the onboarding flow (currently a mobile
   step-by-step wizard) should be reconsidered for a wide viewport once the shell exists. Decide whether
   onboarding happens *inside* the desktop shell (e.g. a modal/centered card over the dashboard) or as its own
   pre-shell full-page flow (closer to how Notion/Linear present first-run setup) — don't just stretch the
   phone wizard to full width and call it done.

## Open decisions to make before/during implementation

- Exact breakpoint(s) — desktop-only, or also a tablet-width intermediate layout?
- Which mobile tabs map 1:1 to sidebar items, and whether the web dashboard's *default landing view* should
  differ from mobile's (e.g. a richer "today" dashboard vs. mobile's current home screen) — the ElevenLabs
  reference's home screen is richer/more grid-heavy than a typical mobile home tab, and that may be the right
  call here too given the extra width available.
- Whether search (top bar, à la ElevenLabs' "Search everything...") is in scope for v1 or a fast-follow.

## Deliverable

- A working `DesktopAppShell` (sidebar + top bar) that activates above the chosen breakpoint, wrapping the
  same screens mobile already uses.
- Onboarding adapted for wide viewports per the decision above.
- Visual sign-off against the design system — this should look like a natural sibling of the ElevenLabs-style
  reference, in this app's own palette, not a mobile screen with more whitespace.
