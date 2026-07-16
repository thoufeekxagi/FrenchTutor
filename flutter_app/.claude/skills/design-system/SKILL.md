---
name: design-system
description: Color, typography, spacing, motion, and icon tokens for this app's "Passeport" native-iOS design system. Use whenever adding or restyling any Flutter widget, screen, or theme file in this project — covers what colors/fonts/sizes/curves to use and why, so visual choices stay consistent instead of ad hoc.
---

# Design system — tokens

Full rationale lives in [`design.md`](../../../design.md) at the project root — read it if you
need the "why," not just the "what." This skill is the token reference for day-to-day styling.

## Color — plug-and-play palettes

Colors are a swappable layer. Palettes live in `lib/design/palettes.dart` as classes with
identical static-const slots; `lib/design/tokens.dart` picks the active one with ONE line:

```dart
typedef _Palette = ProSystemAzure;   // ← swap this line, rebuild, whole app re-skins
```

**To adopt a new palette from a marketing mockup** (`marketing/color-palette/*.jpg`): copy an
existing class in `palettes.dart`, rename it, fill the hex values from the mockup, flip the
typedef. Never edit token values directly; never hardcode `Color(0x...)` in widgets.

**Active palette: Pro System Azure** (`marketing/color-palette/pro_system_azure.jpg`).
Screens reference tokens via `Passeport.*` (alias) or `DesignTokens.*`. Semantic names are
canonical; Passeport-era names still resolve (parchment→canvas, card→surface, maroon→primary,
brass→mastery, sage→success, sky→info, slate→muted):

| Token (semantic) | Azure hex | Use |
|---|---|---|
| `ink` / `inkSoft` | `#1C1E21` / `#33383F` | primary text, headings / secondary dark text |
| `canvas` / `canvasDim` | `#F8F9FA` / `#EEF0F2` | app background / subtle section background |
| `surface` | `#FFFFFF` | card/sheet surfaces |
| `primary` (+`Deep`,+`Soft`) | `#007BFF` | THE action color: buttons, links, active states |
| `secondary` | `#17A2B8` | secondary CTAs, accents |
| `success` (+`Soft`) | `#28A745` | valid, complete, speaking-ready |
| `info` (+`Soft`) | `#17A2B8` | guidance, information |
| `mastery` (+`Soft`) | `#FFC107` | demonstrated mastery only |
| `warning` (+`Soft`) | `#FFC107` | cautions, alerts |
| `danger` (+`Soft`) | `#DC3545` | errors, invalid, destructive |
| `muted` / `mutedDim` | `#A0A0A0` / `#707070` | tertiary text, disabled, captions |
| `hairline` | ink @ 9% alpha | borders on light surfaces |
| `hairlineLight` | canvas @ 16% alpha | borders on dark/inverted surfaces |

One primary per screen: azure marks the single dominant action; everything else stays neutral
or uses its semantic state color. Don't recolor tiles decoratively — color = action or
learning state. When adding a new slot, add it to EVERY palette class in `palettes.dart`.

## Typography

Two families, used deliberately (not SF Pro — this is an intentional brand deviation, see
`design.md` §2):
- **Display / headings** — `Passeport.display(size, {weight})` → Playfair Display serif.
- **Body / UI text** — `Passeport.body(size, {weight})` → system sans.
- **Data / numbers / code** — `Passeport.mono(size, {weight})` → JetBrains Mono.

Even though the typeface differs from SF Pro, still respect Apple's *scale* and floor:
- Large title ~34, section title ~22–28, headline ~17 (semibold), **body 17**, caption ~12–13.
- **Never go below 11pt** anywhere (Apple's Dynamic Type accessibility floor).
- Support Dynamic Type: don't hardcode pixel layouts that break if system text scale increases;
  test screens at larger accessibility text sizes before shipping a change.

## Spacing & sizing

- Base spacing unit: 4pt. Common gaps in existing screens: 4, 8, 12, 16, 20, 24 — stick to this
  scale rather than arbitrary values like 18 or 22.
- Screen horizontal padding: 20pt (see `labs_screen.dart`).
- Card/tile corner radius: 14pt (see `PasseportCard`, `_LabTile`). Buttons: 10pt
  (`PasseportPrimaryButton`). Keep corner radii consistent within a visual tier — don't mix 8/12/14
  for the same kind of surface.
- **Minimum tap target: 44×44pt**, no exceptions — this is an Apple HIG hard floor backed by
  measurable tap-error-rate research, not a style preference.

## Motion

- Prefer `Curves.easeOutCubic` or a low-bounce spring (`SpringDescription` near critical damping)
  for entrance/transition animations.
- **Avoid `Curves.elasticOut` or any heavy-overshoot curve** — Apple's own WWDC23 spring guidance
  warns that bounce values above ~0.4 read as "too exaggerated"; overshoot reads as cheap/toy-like
  on iOS, not delightful.
- Scrollables must use bouncing/rubber-band physics (the iOS default) — never
  `ClampingScrollPhysics`. If you add a custom `ScrollBehavior`, override `getScrollPhysics()` to
  return `BouncingScrollPhysics()`.
- Celebratory motion (milestones, completions) should be a soft fade/scale, never confetti or a
  bouncy pop — see `ui-patterns` skill for why (no gamification chrome).

## Iconography

- Use `CupertinoIcons.*` (SF Symbols–equivalent), not `Icons.*` (Material). Every current use of
  `Icons.chevron_right`, `Icons.headphones_rounded`, etc. is a "not native" tell and should be
  migrated when that file is next touched.
- Icon sizing: 20–28pt inline with text/list rows (matches current `_LabTile` usage), 25×25pt for
  tab bar icons (Apple's own tab bar spec).
