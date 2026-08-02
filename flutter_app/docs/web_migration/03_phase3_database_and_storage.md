# Phase 3: Database & Storage for Web

**Status**: Not started. Can run in parallel with Phase 2.

## Current state

`lib/data/database/storage_service.dart` and `learning_store.dart` use Drift on top of native SQLite
(`sqlite3_flutter_libs`). This is genuinely the best-case subsystem for web support: Drift ships an official
web backend (`drift/wasm`, backed by IndexedDB/OPFS), and it uses the **same generated schema, same queries,
same migrations** as native. A web-compatible `web/sqlite3.wasm` file is already sitting in this repo's `web/`
directory from earlier exploration — confirm it's current with the Drift version in `pubspec.yaml` before
relying on it.

## Recommended approach

1. Locate (or create) the single place the app constructs its Drift `QueryExecutor`/database connection.
2. Give it a conditional-import split: native connection factory (existing behavior, untouched) vs a
   `drift/wasm` factory for web. Every `AppDatabase`/DAO/query in the rest of the codebase is unaffected —
   Drift's generated code doesn't care which executor it's talking to.
3. Verify migrations in `app_migrations.dart` run cleanly against the wasm backend — Drift migrations are
   backend-agnostic by design, but worth an explicit test pass since this repo's migration history is now
   fairly long.

## Open architectural question: how much do we even need local-first on web?

The app already syncs to Supabase (`sync_service.dart`). On mobile, local SQLite-first-then-sync exists
mainly for offline resilience and native app snappiness. On web:

- Users are online by definition to load the app at all.
- A browser tab's local storage is less durable than a native app's local file (user can clear site data more
  casually than uninstalling an app).

**Recommendation to evaluate, not a final decision**: consider whether the web build can skip local
Drift/IndexedDB storage entirely for v1 and read/write Supabase directly as source of truth, using
`sync_service.dart`'s existing Supabase-side logic without the local-cache half. This would be *simpler* than
replicating the full offline-first design in a browser, at the cost of needing a network round-trip for reads
that are instant on mobile. Given the "high-end web app" bar the founder wants, watch UI responsiveness here —
if reads feel sluggish, a lightweight in-memory (not persisted) cache layer may be a good middle ground before
committing to full IndexedDB parity.

## Deliverable

- Working Drift web backend behind the same interface as native, OR a documented decision to bypass local
  storage on web in favor of direct Supabase reads, with the tradeoff explicitly written down here.
- Existing DB-dependent tests (`competency_graph_test.dart`, `evidence_store_test.dart`, etc.) passing against
  whichever backend web ends up using.
