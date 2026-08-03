# Phase 4: Database & Storage for Web

**Status**: **Complete and verified in a real browser.**

The conditional-import opener already existed (`database_opener.dart` → `database_opener_web.dart`), and this
session confirmed it actually works end to end rather than just reading correctly: a `--release` web build was
loaded in a browser and IndexedDB afterwards contained the `parlesprint` database with **200 blocks / 819,200
bytes across the `blocks` and `files` object stores**. That is a real SQLite file with the full migration chain
applied and content seeded, persisted through `IndexedDbFileSystem`.

No code changes were needed. The decision below about possibly skipping local storage on web is therefore moot
for now: offline-first works on web as-is, with the same schema, queries, and migrations as native.

## Current state (updated after Phase 1 audit)

`lib/data/database/storage_service.dart` and `learning_store.dart` use Drift on top of native SQLite. The
conditional-import split this phase calls for **already exists**: `lib/data/database/database_opener.dart`
exports `database_opener_native.dart` (native `sqlite3` + `path_provider`) or `database_opener_web.dart`
(`sqlite3.wasm` + `IndexedDbFileSystem`) depending on platform, and `web/sqlite3.wasm` is already checked in.
`lib/providers/database_provider.dart` already imports the conditional `database_opener.dart`, not a specific
platform file — meaning the wiring looks correct on paper.

**What's actually left for this phase is verification, not implementation**: run a real web build, open the
database, run `app_migrations.dart`'s full migration chain, and read/write a row through
`storage_service.dart`/`learning_store.dart`, end to end, in a browser. Drift migrations are backend-agnostic
by design, but this repo's migration history is long enough that an explicit pass is worth the hour it takes,
rather than assuming it "should just work" because the opener file looks right.

If that verification pass turns up nothing, this phase is close to done already — don't invent new
architecture here where none is needed.

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
