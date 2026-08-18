# ParleSprint Design Approach

This is a mandatory design and implementation guide for every UI change under
`flutter_app/`. Read it before redesigning, compacting, or “beautifying” a
screen. The goal is a calm, obvious iOS-quality interface that preserves the
working product behavior.

## Non-negotiable rules

1. **Preserve behavior first.** A visual request must not remove working
   navigation, audio, loading, purchase, restore, submit, or error behavior.
   Inspect the existing flow before editing it.
2. **One screen, one job.** Write the screen’s single purpose and primary
   action before touching layout. Secondary explanations belong below the
   primary task or behind a deliberate interaction.
3. **Never overlap.** A button, title, card, keyboard, tab bar, safe-area inset,
   floating control, or system UI must never cover another interactive or
   meaningful element. Overlays require reserved layout space or collision
   handling; they must not simply be painted on top of content.
4. **Do not hide the primary action.** On the first viewport, show the title,
   essential context, and the next meaningful action. If the screen is
   intentionally scrollable, place secondary content below a clear visual
   break. Never make a user hunt for the action that completes the screen’s
   purpose.
5. **Use the existing design system.** Reuse `DesignTokens`, shared buttons,
   cards, headers, and adaptive widgets. Do not create screen-local colors,
   typography scales, radii, shadows, or competing spacing systems.
6. **Keep data stable.** A redesign must not replace, reorder, or discard user
   content unless that is explicitly requested. Lists append new items; they do
   not overwrite the first item when a row becomes full. Use stable keys.
7. **Every interaction must look interactive.** Buttons need a press/disabled/
   loading state and a minimum 44×44 logical-point hit target. A tap must not
   become a silent no-op; show an error, retry state, or clear disabled reason.
8. **Text is content, not decoration.** Important text must wrap safely, remain
   legible at larger text sizes, and never be clipped, ellipsized into a wrong
   meaning, or squeezed beside an icon. Shorten secondary copy before shrinking
   primary text.

## Mandatory screen contract

Before implementation, record:

- User arrives to:
- They must understand:
- Primary action:
- Secondary action:
- What changes after success:
- Loading state:
- Empty state:
- Error and retry state:
- Content that must remain visible above the fold:
- Content that intentionally belongs below the fold:

If two actions compete for primary attention, stop and resolve the hierarchy
before coding.

## iOS layout rules

### Safe areas and headers

- Start content inside `SafeArea` and account for the top and bottom insets.
- A back button has its own header zone. Never position it over a title or
  assume a title can begin at the same vertical coordinate.
- Long titles may wrap to two lines. Give them width and vertical space rather
  than letting an icon cover them.
- Keep navigation controls in a predictable leading/trailing area. Do not move
  a back action into a visually unrelated location.
- On screens using a `Stack`, reserve the overlay’s footprint in the underlying
  scroll content. `Positioned` is not a substitute for layout.

### Spacing and hierarchy

- Use generous spacing around the most important content; reduce detail before
  reducing the primary action’s clarity.
- Related content is grouped; unrelated content is separated with whitespace.
- Do not place a large marketing card immediately against a purchase, submit,
  or completion button. Add a clear section break.
- Avoid “everything centered” layouts. Center a short headline or empty state;
  use leading alignment for instructions, lists, forms, and dense content.
- Do not put two visually identical primary buttons on one screen unless their
  destinations and roles are unmistakably different.

### Scrolling

- The first viewport is a priority decision, not an accidental crop.
- Make the top section self-contained: title, context, primary choice/action.
- Put supporting stories, comparisons, route illustrations, and long-form
  marketing below the purchase/action area with intentional spacing.
- Ensure the final content and final button can scroll above the bottom safe area
  and keyboard. Never rely on a partial card at the bottom of the viewport.
- Test both the shortest and longest realistic text before choosing fixed
  heights. Prefer intrinsic height, `Flexible`, `Expanded`, and constraints.

### Responsive checks

Test at minimum:

- narrow iPhone width;
- regular iPhone width;
- large iPhone width;
- iPad width;
- Dynamic Type / large text;
- keyboard-visible state when applicable;
- landscape if the feature permits it.

Use available constraints, not device-name checks. A layout that only works in
one screenshot is unfinished.

## Components and interaction patterns

### Cards, rows, and grids

- Use one reusable card shape for the same content type across sessions.
- Keep image aspect ratios consistent; use the reading card as the reference
  when a universal practice card is requested.
- Preserve stable IDs and stable ordering.
- When a row reaches its capacity, create the next row and retain all previous
  items. Never use a fixed visible slice that silently drops older content.
- Avoid nested cards unless the nesting communicates a real hierarchy.

### Floating and draggable controls

- A floating control must move in the same direction as the finger.
- Clamp its position inside safe bounds and keep it clear of the tab bar,
  keyboard, primary buttons, and system gestures.
- Persist position only if that improves usability; reset invalid saved
  positions after rotation or a size-class change.
- Limit its visibility to the screens that actually need it.

### Loading, error, and network states

- Loading UI must explain what is happening without duplicating the same
  message in multiple prominent lines.
- Use a compact progress indicator that does not cover the action it replaces.
- Keep retry available for recoverable failures.
- Never silently fall through to a wrong provider, stale data, wrong voice, or
  unrelated content. If a fallback is required for product behavior, make it
  explicit and test it; otherwise fail with a useful error.
- A completed request must visibly update the screen or show why it did not.

### Paywalls and subscriptions

- Show the billed amount and billing period clearly and prominently.
- Trial or introductory pricing is subordinate to the total billed amount.
- Keep plan selection easy to compare: duration, localized price, renewal
  terms, and one clear subscribe action.
- Include Restore Purchase and Terms/Privacy access.
- Do not duplicate the same price card in two places unless the second is a
  compact sticky action with a distinct purpose.
- Keep the paywall calm: value first, clear choice second, supporting route or
  marketing content below the decision.

### Audio and media

- A play button must visibly transition through idle, loading, playing, and
  error states.
- Loading indicators must not cover the play/pause control.
- Do not change audio source identity, cache keys, tutor voice, or fallback
  policy during a visual-only redesign.
- If an asset is required, validate its existence and identity before shipping.

## Flutter implementation guardrails

- Prefer `SafeArea` + `ListView`/`CustomScrollView` for long screens.
- Do not use `Stack` for ordinary layout. Use it only when layering is the
  actual interaction model.
- When using `Positioned`, reserve equivalent space in the scrollable content.
- Avoid fixed-height containers around variable text.
- Use `Semantics` for icon-only controls and meaningful labels for primary
  actions.
- Use `ValueKey`/stable model IDs for repeated content.
- Keep business logic and navigation intact; extract a reusable visual widget
  rather than duplicating a second implementation.
- Use `lib/design/tokens.dart` and existing shared widgets before adding a new
  primitive.

## Required redesign workflow

1. Read this file, `AGENTS.md`, `design.md`, and the target screen.
2. Inspect the current flow and identify all states and entry points.
3. Write the screen contract above.
4. Make the smallest change that achieves the requested hierarchy.
5. Check narrow width, large text, loading, error, empty, and completed states.
6. Run `dart format`, focused `flutter analyze`, focused tests, and
   `git diff --check`.
7. Capture or inspect screenshots at representative iPhone sizes.
8. Report what changed, what was tested, and any unverified device-only behavior.

## Definition of done

A redesign is done only when:

- no control or text overlaps another element;
- the primary action is obvious and reachable without unnecessary scrolling;
- secondary content is visually subordinate and intentionally placed;
- text survives localization and Dynamic Type reasonably;
- loading, error, disabled, and success states are understandable;
- existing data and behavior remain intact;
- the screen uses shared design tokens/components;
- focused analysis/tests pass;
- screenshots have been checked on a narrow and regular iPhone layout.

## Copy-paste instruction for a design agent

> Before editing UI, read `flutter_app/design_approach.md`, `flutter_app/AGENTS.md`,
> `flutter_app/design.md`, and the target screen. Preserve existing behavior and
> data. State the screen contract, identify the primary action, reserve safe-area
> space for navigation and overlays, and keep secondary content below the first
> decision. Do not overlap, clip, replace list items, duplicate primary buttons,
> or create silent no-ops. Test narrow iPhone, regular iPhone, large text,
> loading, error, and success states. Run formatting, focused analysis/tests,
> `git diff --check`, and report any device-only behavior not verified.

## Apple references

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios/)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [In-app purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase)
