# FrenchTutor (ParleSprint) agent rules

Product: TCF Canada exam-prep app for adult beginners (A1 to B2), deterministic
authored lessons, Gemini Live tutor (Marie) on every lesson.
Branch for v3: `tcf-v3`. Restore point tag: `pre-v3-2026-10-12`.

Before doing anything, read `docs/v3/AGENT_RULES.md`. Then the file that matches
the task:

- Testing or running on the iPhone: `docs/v3/TESTING.md`
- Architecture, entitlements, review safety: `docs/v3/BUILD_STRUCTURE.md`
- Any screen or UI: `docs/v3/UI_STRUCTURE.md`
- Any lesson or syllabus work: `docs/v3/CONTENT_AUTHORING.md`

Fast commands (from `flutter_app/`): `tool/check.sh --quick`,
`tool/check.sh [tests]`, `tool/e2e.sh integration_test/<file>_test.dart`,
`tool/device.sh list|relaunch|logs|run`, `python3 tool/screen_map.py --find <x>`.

Hard rules: evidence before action (no assumed buttons or screens), one heavy
job at a time, two failed attempts then stop and ask, never commit secrets,
never push unless asked, never delete files you did not create.
