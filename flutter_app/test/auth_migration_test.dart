import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/database/learning_store.dart';

void main() {
  group('migration v7: referred_by_code + linkSupabaseUser', () {
    test('profiles table gains a nullable referred_by_code column', () {
      final db = sqlite3.openInMemory();
      final store = LearningStore(db);
      // profile() creates the row if none exists yet.
      final profile = store.profile();
      final rows = db.select(
        'SELECT referred_by_code FROM profiles WHERE id = ?',
        [profile.id],
      );
      expect(rows, hasLength(1));
      expect(rows.first['referred_by_code'], isNull);
    });

    test('linkSupabaseUser stamps user_id on the live profile row', () {
      final db = sqlite3.openInMemory();
      final store = LearningStore(db);
      final profile = store.profile();

      store.linkSupabaseUser('11111111-1111-1111-1111-111111111111');

      final rows = db.select('SELECT user_id FROM profiles WHERE id = ?', [
        profile.id,
      ]);
      expect(rows.first['user_id'], '11111111-1111-1111-1111-111111111111');
    });

    test('linkSupabaseUser is idempotent — calling it twice is harmless', () {
      final db = sqlite3.openInMemory();
      final store = LearningStore(db);
      store.profile();

      store.linkSupabaseUser('aaaa');
      store.linkSupabaseUser('bbbb');

      final rows = db.select('SELECT user_id FROM profiles');
      expect(rows, hasLength(1));
      expect(rows.first['user_id'], 'bbbb');
    });

    test('linkSupabaseUser never touches a soft-deleted profile row', () {
      final db = sqlite3.openInMemory();
      final store = LearningStore(db);
      final profile = store.profile();
      db.execute(
        "UPDATE profiles SET deleted_at = '2026-01-01T00:00:00Z' WHERE id = ?",
        [profile.id],
      );

      store.linkSupabaseUser('should-not-apply');

      final rows = db.select('SELECT user_id FROM profiles WHERE id = ?', [
        profile.id,
      ]);
      expect(rows.first['user_id'], isNull);
    });

    test('linkSupabaseUser adopts only anonymous onboarding trial evidence', () {
      final db = sqlite3.openInMemory();
      final store = LearningStore(db);
      store.profile();
      db.execute(
        "INSERT INTO ai_sessions (id, stage, created_at, updated_at) VALUES ('trial-ai', 'trial', '2026-09-01', '2026-09-01')",
      );
      db.execute(
        "INSERT INTO ai_sessions (id, stage, created_at, updated_at) VALUES ('other-ai', 'speaking', '2026-09-01', '2026-09-01')",
      );
      db.execute(
        "INSERT INTO sessions (id, started_at, stage) VALUES ('trial-session', '2026-09-01', 'trial')",
      );
      db.execute(
        "INSERT INTO sessions (id, started_at, stage) VALUES ('other-session', '2026-09-01', 'speaking')",
      );
      db.execute(
        "INSERT INTO messages (uuid, session_id, role, content) VALUES ('trial-message', 'trial-session', 'user', 'Bonjour')",
      );
      db.execute(
        "INSERT INTO messages (uuid, session_id, role, content) VALUES ('other-message', 'other-session', 'user', 'Bonjour')",
      );

      store.linkSupabaseUser('new-user');

      expect(
        db
            .select("SELECT user_id FROM ai_sessions WHERE id = 'trial-ai'")
            .first['user_id'],
        'new-user',
      );
      expect(
        db
            .select("SELECT user_id FROM ai_sessions WHERE id = 'other-ai'")
            .first['user_id'],
        isNull,
      );
      expect(
        db
            .select("SELECT user_id FROM sessions WHERE id = 'trial-session'")
            .first['user_id'],
        'new-user',
      );
      expect(
        db
            .select("SELECT user_id FROM messages WHERE uuid = 'trial-message'")
            .first['user_id'],
        'new-user',
      );
      expect(
        db
            .select("SELECT user_id FROM messages WHERE uuid = 'other-message'")
            .first['user_id'],
        isNull,
      );
    });
  });
}
