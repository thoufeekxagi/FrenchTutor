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

Echo rule (hard): the microphone sends nothing to a model while the phone is
making sound (tutor voice, its tail, any app clip), on every route including
AirPods. Everything goes through `lib/services/mic_echo_gate.dart` and
`AudioStreamingService.blockMicUntil`. Any new audio path that can play while a
call is open must close the mic for its length plus the tail. See
`docs/v3/AGENT_RULES.md` section 7.

Start here: `docs/v3/README.md` (index, handoff, how to test fast, how to author units).
