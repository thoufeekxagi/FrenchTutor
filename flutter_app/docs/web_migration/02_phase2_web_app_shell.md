# Phase 2: Web App Shell (Desktop Navigation & Layout)

**Status**: Not started. Should land early — every other web screen gets embedded into whatever shell this
phase builds, so get the shell right before wiring real content into it.

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
