import 'package:sqlite3/common.dart';

/// Wipes every per-user table from the local cache. Called on sign-out so a
/// different account signing in on the SAME device — a shared family phone,
/// a resold device, an app-review tester switching accounts — never sees
/// the previous account's learning data. Before this existed, local reads
/// had no per-user scoping at all (`SELECT * FROM sessions`, no `WHERE
/// user_id = ...`), so a second account signing in on the same install
/// would see the first account's entire history until Supabase sync
/// happened to overwrite it — which is additive, not a wipe, so old data
/// could linger indefinitely.
///
/// `schema_migrations` (migration bookkeeping) and `installations` (the
/// device-identity row used for device-level abuse prevention — see
/// `PilotInfrastructureStore` — a NEW installation_id on every sign-out
/// would let a device repeatedly reset its limits) are
/// device-level, not user-level, and are deliberately kept.
void wipeLocalUserData(CommonDatabase db) {
  const keep = {'schema_migrations', 'installations'};
  final tables = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table'")
      .map((r) => r['name'] as String)
      .where((name) => !keep.contains(name))
      .toList();
  db.execute('BEGIN');
  try {
    for (final table in tables) {
      db.execute('DELETE FROM $table');
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
