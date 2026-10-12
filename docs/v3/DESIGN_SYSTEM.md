# V3 design system

Single source of truth in code: `lib/design/appearance_colors.dart` (values),
`lib/design/tokens.dart` (semantic names), `lib/design/app_theme.dart` (Material
theme). Screens never hardcode colors. Appearance state:
`lib/services/app_appearance_settings.dart` (light default, persisted).

## Why these colors (evidence)

Measured from the reference screenshots (dominant saturated and background
colors across frames):

| App | Canvas | Accent |
|---|---|---|
| Speak | white / light gray (#FFFFFF, #F0F0F0) | confident blue (about #0050FF) |
| Babbel | white and warm cream | orange (about #FF5000), yellow secondary |
| Memrise | cream with teal | gold (about #F0C040) |
| Vocabulary.com | warm off-white | green |

Research: a 2026 study of 100 participants across healthcare, finance and
education apps found cool blue/green interfaces produced higher trust,
calmness and comfort than warm red/orange ones, which felt urgent in serious
contexts. TCF is a high-stakes exam, so the action color is a calm blue.

Decision: Speak's blue on Babbel-style white and light gray surfaces. Green
only for correct. Gold kept only for mastery and targets (continuity with the
shipped brand, never an action color). Dark stays black with a lighter blue.

## Palette

| Role | Light | Dark |
|---|---|---|
| canvas | #F5F6F8 | #08090B |
| surface | #FFFFFF | #151619 |
| raised (inputs, chips) | #ECEEF2 | #1D1E21 |
| text | #14171C | #F7F5F0 |
| muted text | #5F6673 | #A7A7A8 |
| hairline | #E1E4EA | #303136 |
| action (primary) | #2563EB | #6B9BFF |
| action soft | #E8EFFE | #14213F |
| on action | #FFFFFF | #08090B |
| success | #15803D | #4ADE80 |
| danger | #C62828 | #F87171 |
| mastery / target | #B97823 | #F2B84B |

Contrast intent: body text 4.5:1 or better, large text and icons 3:1.
White on #2563EB is 5.2:1. Check any new pairing before using it.

## Rules

1. One action color per screen. Blue means "you can act". Gold means "your
   goal/mastery". Green means "correct". Red means "fix this".
2. Light surfaces separate with a hairline and a soft shadow, dark surfaces
   with tone only.
3. Toggle lives in Settings > Preferences > Dark mode (key
   `settings.darkMode`). Default is light for every install. Changing it
   rebuilds the whole app tree (the MaterialApp is keyed by mode), so DesignTokens'
   static reads stay correct.
4. Typography: Plus Jakarta Sans for headings, Inter for everything else.
5. Hardcoded `Colors.white/black/Color(0x...)` in screens is a bug waiting for
   the other appearance. About 270 exist today. Replace them with tokens when
   a screen is touched, and check both modes with `E2E_DARK`.

## Verifying a screen in both modes

```
tool/e2e.sh integration_test/explore_test.dart                       # light
E2E_DEFINES='--dart-define=E2E_DARK=true' tool/e2e.sh integration_test/explore_test.dart   # dark
```
Look at `artifacts/e2e/shots/*.png` in each. Copy a run elsewhere before the
next one wipes it.
