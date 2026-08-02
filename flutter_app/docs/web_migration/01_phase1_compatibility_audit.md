# Phase 1: Web Compatibility Audit

**Status**: Not started.

**Goal**: produce a concrete, file-by-file list of what needs to change before this codebase runs correctly
as a web app. This phase makes no code changes — it's reconnaissance so Phases 2-5 have no surprises.

## Method

Walk `pubspec.yaml` dependencies and everything under `lib/services/` and `lib/data/`, and tag each one:

- **Shared as-is** — pure Dart, no native plugin dependency. No action needed.
- **Needs a conditional-import shim** — the package already has (or can get) a web-compatible backend; the
  fix is a thin platform-specific implementation behind an existing or new interface.
- **Needs real new code** — no drop-in web equivalent exists; budget this as actual engineering work, not a
  config change.

## Known findings so far (from initial review — verify and expand during Phase 1 execution)

| Package / file | iOS/Android today | Web status | Bucket |
|---|---|---|---|
| `sqlite3_flutter_libs` + `drift` (`lib/data/database/`) | native SQLite | `drift/wasm` exists; `web/sqlite3.wasm` is already present in this repo | Shim (see Phase 3) |
| `flutter_sound` (voice call audio) | native mic streaming | web has different APIs, real latency/streaming differences | Real new code (see Phase 4) |
| `google_sign_in` | native SDK | has a web implementation, but flow differs (redirect vs native sheet) | Shim |
| `sign_in_with_apple` | native SDK | Apple's web Sign-In JS flow, or drop Apple sign-in on web entirely (decide in Phase 2) | Shim or scope-cut |
| `purchases_flutter` (RevenueCat) | native IAP | no native IAP on web at all | Real new code / different vendor (see Phase 2) |
| `permission_handler` | native permission dialogs | browser permission prompts | Shim (usually low effort) |
| `supabase_flutter` | works cross-platform already | works cross-platform already | Shared as-is (already true) |
| Business logic: SRS, competency graph, evidence store, lesson agent orchestration, prompts, content models | pure Dart | pure Dart | Shared as-is |
| Screens/UI (labs, lessons, onboarding, settings, etc.) | pure Flutter widgets | pure Flutter widgets | Shared as-is (verify no native-only widget dependencies snuck in, e.g. platform-specific `showCupertinoModalPopup` conditionals that assume iOS) |

## Deliverable

A completed version of the table above, covering every file in `lib/services/` and `lib/data/database/`, plus
every plugin in `pubspec.yaml` with a platform-specific implementation. Paste the final table into this file
(replacing "Known findings so far") once the audit is done, and update the Status line to **Complete**.

## Out of scope for this phase

Do not start implementing shims yet — that's Phases 2-4. This phase only produces the list.
