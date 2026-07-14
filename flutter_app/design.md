# Design Reference — One ParleSprint Vibe, Native Mechanics Everywhere

This is the permanent design reference for ParleSprint. The app is Flutter shipping to
**iOS, Android, and web from one codebase**, and the product is deliberately **not** a gamified
consumer app (no Duolingo-style streak guilt, mascots, or confetti) — it's positioned as a
"hardcore but clean" tool for adult learners who want to actually learn French, closer in spirit
to an exam-prep tool than a habit-loop game.

**The one-vibe rule (decided 2026-07):** the app must feel like the SAME premium product on every
platform. Visual identity (palette, type, icons, cards, segmented pills, spinners' calm pacing,
no-ripple taps) is **brand-first and identical everywhere**; only the *mechanics* that users feel
in their hands adapt per platform (page-transition style + edge-swipe back on iOS, dialog frame,
scroll always rubber-bands). Concretely: CupertinoIcons on ALL platforms, `NoSplash` on ALL
platforms, the same hairline-bordered cards everywhere — but `CupertinoPageRoute` only on iOS.

Two Claude skills are derived from this file: `design-system` (tokens: color, type, spacing,
motion, iconography) and `ui-patterns` (navigation, components, screen flows, anti-patterns).
Update this file first when the design direction changes, then regenerate the skills from it.

---

## 0. The implemented wiring (code map — keep in sync)

The design system is CODE, not just prose. Three layers, already built:

| Layer | File | Owns |
|---|---|---|
| 1. Tokens | `lib/design/tokens.dart` (`DesignTokens`) | palette, type ramp (Playfair display / system body / JetBrains mono), 4pt spacing, radii (8/10/14/pill), 44pt tap floor, motion (200/300/450ms, easeOutCubic, never elastic), web breakpoints (600/1024, 560pt content column) |
| 2. Theme | `lib/design/app_theme.dart` (`AppTheme`, `AppScrollBehavior`) | ThemeData from tokens; per-platform `PageTransitionsTheme` (Cupertino on iOS/macOS, Zoom on Android, fade on web); `NoSplash` everywhere; bouncing scroll everywhere |
| 3. Components | `lib/widgets/adaptive/adaptive.dart` + `lib/design/app_router.dart` | `AppRouter.push` (THE only way to navigate — raw `MaterialPageRoute` is banned), `showPSConfirmDialog`, `showPSActionSheet`, `showPSDatePicker` (Cupertino wheel everywhere), `PSSegmented` pills, `PSSwitch`, `PSProgressIndicator`, `PSHaptics` (no-op on web), `PSContentColumn` (centers content ≥600pt wide) |

`lib/config/theme.dart` (`Passeport`) is a thin back-compat alias over `DesignTokens` — existing
screens reference it; new code should import the design layers directly.

Rules enforced in review: no `Platform.isIOS` in screens; no raw `MaterialPageRoute`; no
`Icons.*` (CupertinoIcons only); no elastic/overshoot curves; every tap target ≥44pt.

---

## 1. Product design stance

**Positioning:** premium, editorial, calm — a "passport/field journal" aesthetic, not a
"playground." The `Passeport` identity: pastel French-flag palette (ink `#1B2A4A`, parchment
`#FAF9F6`, maroon `#C8433E`, brass `#6B8FC4`, slate grays), Playfair Display serif for headings,
system sans for body, JetBrains Mono for data/labels. Cards are white with 1px ink-hairline
borders and 14pt radius — depth comes from color and hairlines, never drop shadows. One dominant
action per screen (the Continue button pattern); everything else is quiet.

**What we are explicitly avoiding**, backed by research into why these read as manipulative or
juvenile for a serious/adult audience:

- **Streak mechanics as loss-aversion pressure.** Streaks reframe the goal from "learn French"
  to "don't break the number" — critics describe this as a dark pattern exploiting loss aversion
  rather than intrinsic motivation. If we show consistency at all, frame it as a calm log
  ("12 sessions this month"), never a flame icon or a warning that it's about to reset.
- **Anthropomorphized mascots driving guilt notifications.** Duolingo's owl is a deliberate
  retention lever — sad-owl notifications create "anthropomorphic stakes." No mascot, no
  character-voiced push copy.
- **Badges/confetti/leaderboards as default-on flourishes.** Industry commentary treats these as
  tools to use "selectively"; overused they read as noise once novelty wears off, which is the
  wrong trade for a tool used daily for serious study. Reserve celebratory motion (if any) for
  genuinely rare milestones, and keep it understated (a soft fade/scale, never confetti).
- **Candy-color palettes and bubble/rounded "friendly" type.** These read as casual-consumer-habit
  product design. Keep the existing restrained palette and serif/mono type pairing rather than
  drifting toward saturated primaries and rounded display faces.

**Steelman / when to reconsider:** gamification isn't inherently wrong — it's a legitimate,
proven retention tool (Duolingo's own scale is evidence). We're choosing to avoid it because it
doesn't match this product's positioning (serious adult learner, exam/fluency goal), not because
it's universally bad design.

---

## 2. Apple HIG — load-bearing facts

**Typography (SF Pro / Dynamic Type).**
- SF Pro Text for text ≤19pt, SF Pro Display for text ≥20pt — Text has wider tracking/heavier
  strokes for legibility at small sizes; Display has tighter tracking for headline sizes.
- Dynamic Type scale (default/Large size): Large Title 34pt, Title 1 28pt, Title 2 22pt,
  Title 3 20pt, Headline 17pt (semibold), **Body 17pt**, Callout 16pt, Subhead 15pt, Footnote
  13pt, Caption 1 12pt, Caption 2 11pt. 11pt is the accessibility floor — never go smaller.
- Supporting Dynamic Type (system font scaling) is not optional for an accessible app; test at
  larger accessibility sizes, not just the default.
- We use Playfair Display (serif) for display/headline roles and system/mono for everything else
  — that's a deliberate deviation from SF Pro for brand voice, which is fine, but body text at
  small sizes should still follow the *scale* (17pt body, 11pt floor) even if the *typeface*
  differs from Apple's default.

**Layout / tap targets.**
- Minimum tap target: **44×44pt** — this is Apple's own research-based floor; smaller targets
  measurably increase tap-error rates, especially for anyone with reduced motor precision.
- Standard iOS tab bar: ~49pt tall, icons ~25×25pt, **3–5 tabs** recommended (more tabs shrinks
  each tap target and adds cognitive load — relevant since this app has 5 sections: Home, Labs,
  Progress, History, Settings — that's at the upper edge of "still fine," don't add a 6th).

**Navigation model.**
- Push/pop stack navigation (`CupertinoPageRoute`) for drilling into content — must preserve the
  **edge swipe-to-pop back gesture**; this is one of the most-felt native cues and easy to break.
- Sheets (modal presentation) for focused, self-contained tasks (e.g., starting a session,
  editing settings) — not full-screen pushes for things the user should be able to dismiss with a
  downward swipe.
- Tab bar for top-level sections only; don't nest another tab bar inside a tab.
- Action sheets (`CupertinoActionSheet`) for a set of mutually exclusive destructive/contextual
  choices; alerts (`CupertinoAlertDialog`) for a single decision/confirmation, not for content.

**Materials & depth.**
- iOS communicates hierarchy via **translucency/blur/vibrancy** (frosted glass — nav bars, tab
  bars, sheets), not via Material-style cast shadows and elevation. Use `BackdropFilter` +
  semi-transparent surfaces to approximate this instead of `Material`/`Card` elevation shadows.
- Corner radii and blur should be consistent app-wide — treat them as tokens, not per-widget
  choices (see `design-system` skill for the actual values in use).

**Motion.**
- Apple's own spring model (WWDC23 "Animate with springs") is parameterized by `duration` +
  `bounce`; Apple explicitly warns **bounce above ~0.4 "may feel too exaggerated."** System
  defaults sit in the low-bounce "smooth"/"snappy" range.
- Prefer `Curves.easeOutCubic` or a low-bounce/near-critically-damped spring over
  `Curves.elasticOut` or any heavy-overshoot curve — elastic/bouncy easing reads as cheap/toy-like
  against iOS's crisp, barely-perceptible settle.
- Scrollables must use **bouncing (rubber-band) physics**, never clamped — iOS always overshoots
  and springs back at scroll boundaries; Android-style clamping is an immediate "not native" tell.

---

## 3. Flutter-on-iOS anti-patterns (why the current app doesn't feel native)

Confirmed by codebase audit: **zero Cupertino widgets** anywhere in the app; 20+ files use
Material-only APIs (`MaterialPageRoute`, `ElevatedButton`, `BottomNavigationBar`,
`Icons.chevron_right` etc.) inside a `MaterialApp`. Every item below is currently present or at
risk in this codebase:

1. **Material ripple (`InkWell`/`ListTile` splash)** — iOS has no ripple idiom at all; this is
   one of the fastest "this is a ported Android app" tells. `labs_screen.dart`'s `ListTile` rows
   currently get this by default.
2. **Wrong font rendering** — plain `MaterialApp`/`ThemeData` does not automatically apply SF Pro;
   it must be set explicitly via a `CupertinoThemeData`/`TextTheme` if we want system-font
   fallback anywhere outside the serif/mono brand type.
3. **Clamped scroll physics** — check any custom `ScrollBehavior` doesn't override to
   `ClampingScrollPhysics`; default Cupertino widgets get bouncing physics automatically, but a
   global Material `ScrollBehavior` can silently kill this.
4. **Broken/missing swipe-to-pop** — `MaterialPageRoute` (used everywhere today, e.g.
   `labs_screen.dart`) does not give the iOS edge-swipe-back gesture. Needs `CupertinoPageRoute`
   (or a `PageTransitionsTheme` mapping iOS to `CupertinoPageTransitionsBuilder`) consistently,
   not ad hoc custom `PageRouteBuilder`s that bypass the back-gesture detector.
5. **Material dialogs/pickers/action sheets** — swap `AlertDialog`/Material date pickers for
   `CupertinoAlertDialog`/`CupertinoDatePicker`/`CupertinoActionSheet`, or `.adaptive` variants.
6. **Elevation/shadow-based depth** — replace `Material`/`Card` elevation with blur+vibrancy
   (`BackdropFilter`) where hierarchy needs to read as "layered," e.g. nav bars, sheets.
7. **Material `Switch`/`Checkbox`/`Radio`** — use `Switch.adaptive` or `CupertinoSwitch` explicitly;
   the Material switch shape is an instant visual giveaway.
8. **Generic Material icon set** (`Icons.chevron_right`, `Icons.headphones_rounded`, etc., seen
   throughout `labs_screen.dart`) — replace with `CupertinoIcons` (SF Symbols-equivalent) for
   visual consistency with the rest of iOS.
9. **Over-bouncy animation curves** — see Motion above; audit any custom `AnimationController`
   curves for elastic/heavy-overshoot easing.

**Root-cause fixes (apply once, app-wide, rather than per-screen):**
- Wrap navigation in a `PageTransitionsTheme` mapping `TargetPlatform.iOS` →
  `CupertinoPageTransitionsBuilder`, and migrate `MaterialPageRoute` call sites to
  `CupertinoPageRoute` (or route through a shared `AppRoute.push(context, screen)` helper so this
  is enforced centrally instead of per-callsite).
- Add a shared `ScrollBehavior` override returning `BouncingScrollPhysics()`.
- Prefer `.adaptive` constructors wherever Flutter provides them; fall back to explicit
  `Cupertino*` widgets where it doesn't.
- Swap `Icons.*` → `CupertinoIcons.*` app-wide.

---

## 4. Competitor / reference landscape

**Serious/non-gamified language learning apps** (researched: Babbel, Busuu, and general
consumer-app critique of Duolingo's gamification):
- **Babbel** — "feels like a classroom": structured, research-backed lessons, strong grammar and
  speech-recognition focus, deliberately less game-like than Duolingo. Weaker on variety past
  intermediate levels — a lesson for us on keeping mid/advanced content fresh without resorting
  to game mechanics to paper over repetition.
- **Busuu** — clean, minimal interface prioritizing clarity/speed/smooth navigation; lessons open
  with a native-speaker video then mix comprehension/fill-in-blank/matching interactions. Note:
  Busuu *does* use some gamification (streaks, daily challenges, leaderboard) — so it's a partial
  reference for visual cleanliness, not a full reference for our no-gamification stance.
- **General critique of the gamified model** (Duolingo specifically): reviewers explicitly say
  it "prioritizes profit over instruction and streaks over speaking skills" and recommend
  dedicated tools for people with concrete goals (career/exam/immigration) — this is direct
  validation that a segment of serious learners wants exactly what we're building.

**Takeaway for our app:** borrow Busuu's clarity/speed of navigation and Babbel's structured,
classroom-like content framing, but keep zero gamification chrome (no streak flames, no
leaderboard, no daily-challenge nagging) — closer to a well-made reference tool than either.

**Flutter techniques for native polish — Wonderous (gskinner × Google Flutter team):**
- Deliberately pushes parallax scrolling, hero-style transitions between detail screens, and
  custom-shader visual effects to their limit — useful as a *technique* reference (how to
  structure custom page transitions, parallax scroll effects), not as a *tone* reference (its
  illustrated, vibrant style is the opposite of our restrained "passport" aesthetic).
- Runs on Impeller by default on iOS — worth confirming this app's iOS build also uses Impeller
  for animation performance parity.

**Flutter packages for native iOS feel:**
- `cupertino_icons` — SF Symbols-equivalent icon set (already a Flutter default dependency; just
  needs to actually be used instead of `Icons.*`).
- `flutter_platform_widgets` — single-widget API that renders Cupertino on iOS / Material on
  Android, avoiding manual `Platform.isIOS` branching, if the app ever needs to ship on Android.
- `cupertino_native` / `adaptive_platform_ui` — newer packages hosting real UIKit controls via
  platform views for pixel-perfect native rendering (incl. iOS 26+ Liquid Glass) — worth
  evaluating if Cupertino-widget fidelity isn't enough, but adds platform-view complexity.
- `flutter_animate` — chainable entrance/fade/scale effects for polish without hand-rolling
  `AnimationController`s.
- `flutter_slidable` — iOS-style swipe actions on list rows (e.g. archive/delete a history entry).
- `shimmer` — loading placeholders; use sparingly and only for genuine network/DB fetch latency,
  not as decoration.

---

## 5. Source notes

Anti-pattern and motion findings are backed by: Flutter issue tracker discussions on ripple/font/
scroll-physics/back-gesture behavior, Apple's WWDC23 "Animate with springs" session, and
Apple Developer Documentation (Typography, Tab Bars). Gamification-critique findings are backed
by design-criticism pieces on Duolingo's streak/mascot mechanics and comparative reviews of
Babbel/Busuu. Treat the "steelman" section as a genuine trade-off, not a settled argument —
revisit if user research suggests otherwise.
