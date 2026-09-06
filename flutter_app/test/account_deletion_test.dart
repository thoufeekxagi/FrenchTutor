import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/account_deletion.dart';
import 'package:french_tutor/data/database/local_data_reset.dart';

void main() {
  test('permanent deletion clears every local row but keeps the schema', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    db.execute('CREATE TABLE schema_migrations (version INTEGER)');
    db.execute('CREATE TABLE installations (id TEXT PRIMARY KEY)');
    db.execute('CREATE TABLE profiles (id TEXT PRIMARY KEY, name TEXT)');
    db.execute(
      'CREATE TABLE generated_content (id TEXT PRIMARY KEY, body TEXT)',
    );
    db.execute("INSERT INTO schema_migrations VALUES (40)");
    db.execute("INSERT INTO installations VALUES ('device-1')");
    db.execute("INSERT INTO profiles VALUES ('user-1', 'Learner')");
    db.execute("INSERT INTO generated_content VALUES ('content-1', 'old')");

    wipeLocalDatabase(db);

    expect(db.select('SELECT * FROM schema_migrations'), hasLength(1));
    expect(db.select('SELECT * FROM installations'), isEmpty);
    expect(db.select('SELECT * FROM profiles'), isEmpty);
    expect(db.select('SELECT * FROM generated_content'), isEmpty);
  });

  test('ordinary sign-out clears account rows but keeps device identity', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    db.execute('CREATE TABLE schema_migrations (version INTEGER)');
    db.execute('CREATE TABLE installations (id TEXT PRIMARY KEY)');
    db.execute('CREATE TABLE profiles (id TEXT PRIMARY KEY, name TEXT)');
    db.execute("INSERT INTO schema_migrations VALUES (40)");
    db.execute("INSERT INTO installations VALUES ('device-1')");
    db.execute("INSERT INTO profiles VALUES ('user-1', 'Learner')");

    wipeLocalUserData(db);

    expect(db.select('SELECT * FROM schema_migrations'), hasLength(1));
    expect(db.select('SELECT * FROM installations'), hasLength(1));
    expect(db.select('SELECT * FROM profiles'), isEmpty);
  });
}
