# Home redesign — compact recent activity grid

## Goal

Keep the redesigned Home screen glanceable on a standard iPhone viewport so
the complete four-card Recent activity block is visible above the translucent
navigation island without requiring a scroll.

## Approved change

- Keep the existing Home hierarchy, content, navigation, and actions.
- Keep Change your tutor as the first card.
- Keep the next three generated roadmap lessons as the remaining cards.
- Render the four cards as an equal-width 2×2 grid.
- Use compact cards with balanced horizontal proportions rather than tall
  square cards.
- Use consistent 10pt gaps between columns and rows.
- Keep the tutor portrait and skill-specific lesson icons, but reduce their
  internal footprint so titles remain readable at the compact height.

## Preserved behavior

- Tutor card opens tutor settings.
- Lesson cards open the same course activity session.
- Roadmap selection and generated lesson content are unchanged.
- Bottom navigation remains the existing translucent blurred island.

## Implementation

Implemented in `lib/screens/speak/speak_home_screen.dart`:

- Activity grid uses two equal columns with a 1.34 aspect ratio.
- Card spacing is 10pt horizontally and vertically.
- Cards use 12pt padding and a 16pt radius.
- Tutor image is a compact 48pt-high preview.
- Lesson icons are 34pt circles with compact typography.

## Verification checklist

- [x] Four activity cards remain present.
- [x] Cards retain their original tap destinations.
- [x] No data or navigation logic changed.
- [ ] Visual confirmation on the user's local device remains pending; this
      pass intentionally does not launch an emulator, simulator, or device.
