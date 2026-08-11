# ParleSprint UI/UX stage v2

This branch implements the Stitch **Confident Momentum** direction without
changing product behavior or merging into the active `pilot` checkout.

## Design contract

- Plus Jakarta Sans creates warm, confident headings; Inter remains the
  high-legibility reading and control face.
- Royal blue is the only primary action color. Teal marks speaking/listening,
  amber celebrates momentum, green marks mastery, and coral communicates
  correction or errors.
- Screens use a soft cool canvas, white learning surfaces, 20px card radii,
  14px control radii, restrained depth, and 48px minimum targets.
- Bottom navigation uses one Material 3 treatment on Android, iOS, and web.
- Every screen consumes semantic tokens. Retired visual aliases and direct
  screen-level brand colors are blocked by `test/ui_v2_contract_test.dart`.

## Stitch screen coverage

| # | Experience | Flutter implementation | v2 treatment |
| ---: | --- | --- | --- |
| 1 | Onboarding | `lib/screens/onboarding/onboarding_screen.dart` | Brand gradient, friendly display type, accessible goal/level/tutor choices |
| 2 | Sign in | `lib/screens/auth/auth_screen.dart` | Unified gate gradient, rounded identity controls, clear feedback |
| 3 | Today dashboard | `lib/screens/home/dashboard_screen.dart` | Mission-first hierarchy, momentum surfaces, stronger practice shortcuts |
| 4 | Learning path | `lib/screens/path/path_screen.dart` | Blue path progression, mastery and locked-state semantics |
| 5 | Practice hub | `lib/screens/labs/labs_screen.dart` | Consistent skill cards and learning-state colors |
| 6 | Alphabet | `lib/screens/labs/alphabet_lab_screen.dart` | Large pronunciation targets and clear lesson hierarchy |
| 7 | Vocabulary | `lib/screens/labs/vocab_lab_screen.dart` | Friendly choice surfaces and primary start action |
| 8 | Flashcards | `lib/screens/lessons/flashcard_session_screen.dart` | Focused card surface and semantic grading colors |
| 9 | Grammar | `lib/screens/labs/grammar_lab_screen.dart` | Structured lesson catalogue and progress cues |
| 10 | Listening/story | `lib/screens/lessons/story_reader_screen.dart` | Readable long-form type and guided learning cards |
| 11 | Speaking tutor | `lib/screens/session/session_screen.dart` | Teal speaking identity, accessible live controls, clear transcript states |
| 12 | Speaking mock | `lib/screens/mocks/mocks_screen.dart` | Calm exam setup, timing, and score hierarchy |
| 13 | Writing | `lib/screens/lessons/writing_task_screen.dart` | Focused prompt/composer surfaces and coaching feedback |
| 14 | Scan | `lib/screens/scan/scan_screen.dart` | Image-first workspace and consistent attachment sheet |
| 15 | Camera capture | `lib/screens/scan/camera_capture_screen.dart` | High-contrast capture controls and safe-area behavior |
| 16 | Progress | `lib/screens/progress/progress_screen.dart` | Momentum, mastery, streak, and history roles use fixed semantics |
| 17 | History | `lib/screens/history/all_history_screen.dart` | Scannable chronological activity surfaces |
| 18 | Session detail | `lib/screens/history/history_screen.dart` | Clear summary and transcript hierarchy |
| 19 | Notes | `lib/screens/notes/notes_review_screen.dart` | Readable saved-note cards and purposeful empty state |
| 20 | Settings | `lib/screens/settings/settings_screen.dart` | Grouped controls, consistent list rows, safe destructive actions |
| 21 | Subscription | `lib/screens/subscription/paywall_screen.dart` | Premium hierarchy, benefit clarity, invite redemption, legal access |

## Verification gate

1. `dart format lib test`
2. `dart analyze --no-fatal-warnings lib`
3. `flutter test`
4. `flutter build apk --debug`
5. Launch on an Android emulator and inspect all five tabs plus pushed flows.
