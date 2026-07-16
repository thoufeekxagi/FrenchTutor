# ParleSprint Product Design — Guided Momentum

This document is the product and visual authority for the Flutter app. It replaces earlier “Passeport” and gamified mockup interpretations when they conflict. The implementation ships one branded product across iOS, Android, and web; platform mechanics adapt where users expect them to.

## 1. Product promise

**ParleSprint always knows the next most valuable thing a learner should practice—and can explain why.**

The product is a serious adaptive French coach with light game energy. Its benchmark balance is the structure and clarity of Busuu plus the conversational warmth of Praktika. It must not copy either product. ParleSprint is ownable through:

- transparent competency-based recommendations;
- a governed, resumable daily learning path;
- live coaching with Marie;
- TCF/TEF and real-life goals;
- progress backed by learning evidence.

Every important recommendation answers four questions: what is next, why it matters, how long it takes, and what changes after completion.

## 2. Information architecture

The intended primary destinations are:

1. **Today** — one recommended next session and calm daily momentum.
2. **Path** — the learner competency map: ready, building, blocked, and next.
3. **Practice** — learner-directed speaking, vocabulary, grammar, listening, and writing.
4. **Progress** — evidence of growing ability and goal readiness.

Settings belongs behind a profile control rather than occupying a primary tab. Until Path is implemented, the existing navigation may remain during migration, but new work must not deepen the old information architecture.

## 3. Screen-intent contract

Define this before changing a screen:

- **User arrived to:** the trigger and expectation.
- **They must understand:** the single most important information.
- **Primary action:** the one visually dominant action.
- **Secondary action:** optional and visually quiet.
- **Success state:** what changes after the action.
- **Must not contain:** distractions, duplicate routes, or unsupported claims.

If a screen has two primary intentions, split the flow or demote one. Visual polish cannot repair unclear intent.

## 4. Motivation model

ParleSprint may use light game energy only when it represents real learning:

- reachable checkpoints and a visible path;
- `New → Building → Ready` competency states;
- daily and weekly progress movement;
- completion feedback, subtle motion, and haptics;
- quiet milestones after evidence of mastery.

Do not use XP economies, coins, lives, leaderboards, streak-loss pressure, guilt notifications, mascots, confetti, fake scarcity, or ornamental badges. Consistency can be shown as neutral history such as “3 sessions this week.”

## 5. Visual direction

The direction is **Guided Momentum**: professional enough for an immigration or exam goal, lively enough to invite daily practice.

### Color

Color is a plug-and-play layer. Palettes live in `lib/design/palettes.dart` as classes with
identical slots; `lib/design/tokens.dart` selects the active one with a single typedef line
(`typedef _Palette = ProSystemAzure;`). To try a new direction from a marketing mockup
(`marketing/color-palette/*.jpg`): add a palette class with the same slots, flip the typedef,
rebuild. Nothing else in the app changes.

**Active palette: Pro System Azure** (`marketing/color-palette/pro_system_azure.jpg`) —
professional blue system, high-trust neutrals:

- dark navy ink (`#1C1E21`) for text and headings;
- off-white canvas (`#F8F9FA`), white surfaces for grouping;
- azure blue (`#007BFF`) for the one primary action, links, active states;
- vibrant teal (`#17A2B8`) for secondary call-to-actions, guidance, information;
- emerald (`#28A745`) for success and speaking/listening readiness;
- amber (`#FFC107`) for cautions and for demonstrated mastery;
- crimson (`#DC3545`) for errors and destructive actions only;
- grays (`#A0A0A0` / `#707070`) for tertiary text and disabled states.

Use semantic tokens from `lib/design/tokens.dart` rather than inline colors. Color
communicates action or learning state. It is not used to make every tile different.

### Typography

Inter is the product typeface on every platform. Use scale, weight, line height, and spacing for hierarchy. Large titles are compact and confident; body copy remains readable at system text scaling. Avoid all-caps labels except very short metadata. Never render meaningful text below 11 points.

### Shape and depth

- Content surfaces: 16-point radius.
- Controls: 12-point radius.
- Pills: status, filters, and compact metadata only.
- Prefer open layout and spacing over wrapping every section in a card.
- Shadows are soft and rare. Borders are used for selection or separation, not on every object.

The brand is not literal passport decoration. Do not add maps, wax seals, metallic buttons, paper textures, flags, or travel props merely to signal “French.”

### Motion

Motion explains state change. Use calm 200–350 ms transitions with `easeOutCubic`, restrained fades, progress movement, and platform-native route behavior. Avoid elastic, overshooting, looping, or ornamental motion. Respect reduced-motion preferences when adding nonessential animation.

## 6. Native mechanics

Brand content remains consistent across platforms. Mechanics adapt through shared infrastructure:

- iOS/macOS use Cupertino-style push transitions and edge-swipe behavior where safe;
- Android uses its expected route transition and system dialog behavior;
- branded icons use Cupertino icon geometry consistently;
- dialogs, switches, pickers, and sheets adapt through shared widgets;
- scroll physics and large-screen layout are controlled centrally;
- screens do not branch on platform.

Use `AppRouter` for navigation and shared adaptive primitives from `lib/widgets/adaptive/`.

## 7. Core reference flow

The first visual reference is iOS and covers:

1. Today recommendation;
2. live speaking session;
3. honest session result;
4. return to updated Today state.

Today must present one next action with its reason, expected duration, and position in the daily path. Free conversation with Marie is a secondary practice option.

The live session is the emotional peak: voice-first, minimal controls, obvious listening/speaking/muted state, readable transcript, and safe exit behavior.

The result state reports only captured evidence such as connected duration, learner turns, completion threshold, and saved transcript. It never fabricates pronunciation scores or AI insight.

## 8. Implemented design layers

1. `lib/design/tokens.dart` — semantic color, typography, spacing, radius, motion, and responsive constants.
2. `lib/design/app_theme.dart` — global Flutter theme and platform mechanics.
3. `lib/widgets/` and `lib/widgets/adaptive/` — reusable branded and adaptive primitives.
4. Screens — composition and state only; no independent mini design systems.

`lib/config/theme.dart` remains a compatibility alias while older screens migrate.

## 9. Accessibility and responsive behavior

- Minimum interactive target: 44×44 points.
- Support Dynamic Type/text scaling without clipped fixed-height layouts.
- Maintain WCAG AA contrast for body text and controls.
- Do not rely on color alone for learning status.
- Include semantic labels for icon-only controls.
- Use available width, not device-name checks, for responsive layout.
- Center phone-style content on wide screens until dedicated tablet layouts exist.

## 10. Delivery and visual QA

For each migrated flow:

1. record the screen-intent contract;
2. implement default, loading, empty, error, interrupted, and completed states that apply;
3. format and analyze the code;
4. run focused widget and behavior tests;
5. capture narrow-iPhone screenshots at default and large text scale;
6. compare hierarchy, spacing, contrast, clipping, and interaction state;
7. verify Android mechanics after the iOS reference converges.

A UI change is incomplete if it only looks correct in one happy-path screenshot.
