import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';

/// Deletes every row from every app table, leaving the schema (and the
/// migration bookkeeping) intact so the app keeps working immediately after
/// a "Delete Account" without needing a restart. Reads the table list from
/// sqlite_master rather than a hardcoded list so it never drifts from the
/// actual schema as tables are added.
void wipeLocalDatabase(CommonDatabase db) {
  final tables = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' AND name != 'schema_migrations'",
  );
  for (final row in tables) {
    db.execute('DELETE FROM "${row['name']}"');
  }
}

/// Clears locally-cached preferences (persona choice, API key overrides,
/// roadmap dates, etc.) so a deleted account doesn't leave stale settings
/// behind for whoever signs in next on this device.
Future<void> clearLocalPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}
