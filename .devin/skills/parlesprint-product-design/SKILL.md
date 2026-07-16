---
name: parlesprint-product-design
description: Design, build, or review ParleSprint mobile UI using the Guided Momentum product direction, screen-intent contracts, Flutter primitives, and visual QA workflow.
triggers:
  - user
  - model
allowed-tools:
  - read
  - grep
  - glob
  - exec
  - edit
  - write
---

# ParleSprint product design

Use this skill whenever changing navigation, a screen, a user-facing component, visual tokens, motion, UX writing, or mobile interaction behavior in `flutter_app/`.

Read `flutter_app/design.md` before making UI decisions. It is the product and visual authority. Read the relevant screen, adjacent screens, `lib/design/tokens.dart`, `lib/design/app_theme.dart`, and reusable widgets before editing.

## Required workflow

1. Write the screen contract before implementation:
   - User arrived to…
   - They must understand…
   - Primary action…
   - Secondary action…
   - Success state…
   - Must not contain…
2. Confirm the screen has one dominant intent. Split or demote competing actions.
3. Reuse or extend semantic tokens and shared primitives. Do not introduce inline visual values when a token exists.
4. Preserve real learning and orchestration behavior. Never invent progress, recommendations, scores, or AI feedback for visual effect.
5. Implement the default, loading, empty, error, interrupted, and completed states relevant to the flow.
6. Verify at large text scale and a narrow iPhone viewport. All interactive targets must be at least 44×44 points.
7. Run formatting, analysis, focused tests, then compare simulator screenshots against the approved reference flow.

## Product test

ParleSprint is a serious adaptive French coach with light game energy. It should feel structured like Busuu and conversationally alive like Praktika, but its own identity comes from transparent competency-based recommendations, Marie, and real evidence of progress.

Every important recommendation should answer: what is next, why it matters, how long it takes, and what changes after completion.

## Allowed motivation

Use reachable checkpoints, progress movement, mastery states, weekly goals, subtle motion, haptics, and restrained celebration after real evidence.

Do not use XP economies, coins, lives, leaderboards, streak-loss warnings, guilt copy, mascots, confetti, fake scarcity, or decorative achievement noise.

## Visual rules

- Use the semantic colors in `DesignTokens`: ink, canvas, surface, primary coral, mint success, sky information, and gold mastery.
- One strong color action per screen. Supporting color communicates state, not decoration.
- Use Inter throughout the product. Hierarchy comes from scale, weight, spacing, and composition—not mixing typefaces.
- Prefer open composition over card grids. A card must group related content or provide interaction; it is not default decoration.
- Use 4-point spacing increments, 16-point content surfaces, 12-point controls, and pill geometry only for compact status or filters.
- Use Cupertino icons across branded content for consistency. Adapt platform mechanics in shared navigation/dialog primitives, not inside screens.
- Use calm 200–350 ms motion with `easeOutCubic`. No elastic or ornamental animation.
- Do not reproduce literal passport props, maps, wax seals, metallic controls, or paper textures.

## UX writing

Use short, direct, adult language. Prefer “Next: Listening · 8 min” and “Chosen because…” over motivational filler. Marie is a capable coach, not a mascot. Never claim adaptation or assessment unless the app has real supporting data.

## Review blockers

Block a UI change when it introduces competing primary actions, fake data, hardcoded colors, arbitrary spacing, sub-44-point targets, Material ripple, raw route construction, inaccessible contrast, clipping at larger text sizes, or a new one-off component that duplicates an existing primitive.
