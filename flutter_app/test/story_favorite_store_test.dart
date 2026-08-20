import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/data/database/story_favorite_store.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  test('favorites persist locally and are isolated by owner', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = StoryFavoriteStore(db);

    expect(store.isFavorite('story-1'), isFalse);
    store.setFavorite('story-1', true);
    expect(store.isFavorite('story-1'), isTrue);
    expect(store.favoriteStoryIds(), ['story-1']);

    store.upsertFromRemote(
      userId: 'another-user',
      storyId: 'story-2',
      createdAt: '2026-08-19T12:00:00.000Z',
      updatedAt: '2026-08-19T12:00:00.000Z',
    );

    expect(store.isFavorite('story-2'), isFalse);
    store.setFavorite('story-1', false);
    expect(store.favoriteStoryIds(), isEmpty);
  });
}
