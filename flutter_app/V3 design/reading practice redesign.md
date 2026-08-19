# V3 Reading Practice Redesign

## Status

Implemented first pass on the canonical Flutter app.

## Product contract

Reading is a Practice sub-flow, not a top-level app destination:

```text
Practice → Reading practice workspace → Story reader → Read / Words / Grammar / Quiz / Done
```

The global Home / Course / Practice / Photo navigation is not part of the focused Reading route. The route is presented as an immersive full-screen practice surface and returns to Practice with the native back gesture or back button.

## Visual direction

- Near-black canvas: `#08090B`
- Charcoal surface: `#151619`
- Raised surface: `#1D1E21`
- Warm ivory text: `#F7F5F0`
- Muted text: `#A7A7A8`
- Gold accent: `#F2B84B`
- Plus Jakarta Sans for display text
- Inter for reading text and controls
- English-only learner-facing story headings; French remains inside the reading, listening, and writing content.

## Workspace layout

1. Compact `Reading` header and back action.
2. `Stories matched to your level` context line.
3. `Create a reading story` action.
4. Horizontal topic rail.
5. One large full-width `Continue reading` story card.
6. Older generated stories as compact horizontal rows, approximately half the height of the lead card.

The previous grid of equally sized book cards was removed from this flow. The list is intentionally vertical so the learner can browse older stories without a competing mosaic.

## Preserved behavior

- Story generation and topic selection.
- Profile level and exam-mode generation.
- Generated story persistence and hydration.
- Cover artwork generation and refresh.
- Narration prewarming.
- Story opening and native navigation.

## Not changed yet

- The global Practice landing page styling.
- Other practice shells.
- Full application theme switching. The shared settings service is in place; the app root and other session types still need to consume it.

## Verification

- Targeted Flutter analysis passes with no issues.
- No emulator or physical device was launched.
