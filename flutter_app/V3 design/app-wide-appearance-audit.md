# App-wide appearance audit

Status: source implementation complete — dark mode remains the default and
light mode resolves through the same semantic tokens and persisted setting.

## Product contract

- Dark mode: black/charcoal surfaces, warm white text, gold actions and
  selected states.
- Light mode: white/ivory surfaces, near-black text, the same gold actions and
  selected states.
- No blue or teal brand accents remain. Success and error colors stay semantic
  green/red so feedback is still legible.
- Layout, content, navigation, persistence, and learning behavior do not
  change in this pass.
- The appearance setting is global, but focused-session controls can still
  expose it locally because they write to the same persisted source.

## Screen coverage matrix

Every destination must use the same appearance source at its root surface,
navigation, controls, cards, text, and feedback states.

| Area | Entry points and nested surfaces | Audit points |
| --- | --- | --- |
| App shell | Home, Course, Practice, Photo tutor, Profile/Settings | root background, bottom island, selected tab, icons, labels |
| Home | dashboard, next lesson, quick start, path cards | hero overlay, card surfaces, action buttons, progress |
| Course | roadmap, unit cards, lesson cards, speaking course | unit surfaces, progress, selected lesson, empty states |
| Practice | practice grid, reading, listening, writing, vocabulary, grammar | category cards, filters, progress, modal sheets |
| Speaking | speaking home, course units, guided drill, free talk, roleplay, review | mode cards, phrase cards, recording states, checks, helper controls |
| Reading | story reader, transcript, quiz, keywords, grammar, settings | reader overlay, translation, word highlight, settings panel |
| Listening | generator, player, lyrics/transcript, translation, history | full-bleed overlay, player controls, progress, menus |
| Content | vocabulary, writing workshop, grammar stories, notes/review | cards, answer states, empty/error states, bottom actions |
| Exam | TCF/TEF readiness, practice sections, results | section tabs, timers, score cards, correction states |
| Supporting flows | onboarding, auth, subscription, scan/photo tutor, web shell | backgrounds, buttons, fields, loading/error surfaces |

## Single source of truth

- `lib/services/app_appearance_settings.dart` owns the persisted global
  appearance (`app_dark_mode`) and migrates the existing
  `session_dark_mode` preference.
- `lib/providers/appearance_provider.dart` exposes it to Riverpod roots.
- `lib/design/appearance_colors.dart` contains the black/gold and white/gold
  values.
- `lib/design/tokens.dart` maps legacy and V3 semantic names to the current
  appearance. This prevents older screens from reintroducing the former blue
  palette.
- `lib/design/app_theme.dart` maps both Material themes to the same contract.
- `MainTabScreen` uses the selected appearance for every tab; it no longer
  treats Home as the only dark destination.

## Verification checklist

For each row in the matrix, inspect source-level reachability and confirm:

1. Root background is `DesignTokens.canvas`/`nightCanvas`, not a literal blue
   or a screen-specific white.
2. Cards and sheets use `surface`/`nightSurface` and borders use hairline
   tokens.
3. Primary actions, selected tabs, progress, and active controls use gold.
4. Text uses semantic ink/muted tokens; white is reserved for image overlays
   or intentional high-contrast foregrounds.
5. Empty, loading, error, success, disabled, and modal states follow the same
   appearance.
6. No `Colors.blue`, `Colors.indigo`, `Colors.cyan`, or teal brand token is
   used by the screen.
7. Both `ThemeMode.light` and `ThemeMode.dark` are fed by the same app shell.

## Source-only checks for this pass

- Format changed Dart files.
- Run `dart analyze lib` from `flutter_app` (no compile errors).
- Search for remaining blue/teal literals and legacy tab-only background
  branches.
- Do not launch a simulator, device, browser, or Flutter build in this pass.

## Completed audit result

- `MaterialApp` receives `AppTheme.themeData(darkMode: false)` and
  `AppTheme.themeData(darkMode: true)`, plus the persisted `ThemeMode` from
  the appearance provider.
- Home, Course, Practice, Photo tutor, Profile/Settings, speaking, reading,
  listening, writing, vocabulary, grammar, liaison, and exam roots resolve
  their canvas, surface, hairline, ink, and muted colors through semantic
  tokens.
- Bottom navigation uses one appearance-aware implementation for every tab.
- Former blue/teal learner-facing accents have been removed; gold is the only
  brand selection/action color.
- Onboarding selector and wheel surfaces now use the active surface token
  instead of a literal white background.
- Selected gold controls use the on-primary foreground, while neutral cards
  use appearance-aware text and surface tokens.

## Intentional fixed-contrast exceptions

The remaining literal white/black values are not app-theme surfaces:

- white text/icons over generated artwork, camera previews, marketing hero
  gradients, and full-bleed reading/listening imagery;
- black text/icons placed directly on the gold primary action color;
- the camera preview canvas, which must stay black around the live feed;
- translucent black scrims used to keep lyrics, controls, and story text
  readable over imagery.

These exceptions preserve contrast in both appearance modes and must not be
converted to ordinary canvas or ink tokens.

## Acceptance criteria

The source pass meets this criterion. Device verification is intentionally
left to the owner because this pass does not launch a simulator or build.
