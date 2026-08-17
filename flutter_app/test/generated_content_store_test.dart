import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/generated_writing_task_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('generated writing tasks survive the local store round trip', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = GeneratedWritingTaskStore(db);
    final task = WritingTask(
      id: const Uuid().v4(),
      type: 'micro',
      title: 'A small plan',
      promptFr: 'Écris cinq mots sur ton week-end.',
      promptEn: 'Write five words about your weekend.',
      minWords: 5,
      targetConnectors: const ['et'],
      rubricHints: const ['Use a simple sentence.'],
      levelBand: 'A1',
    );

    store.insert(
      GeneratedWritingTask(task: task, createdAt: DateTime.utc(2026, 8, 17)),
    );
    expect(store.list().single.task.toJson(), task.toJson());

    store.updateCoverUrl(task.id, 'https://example.com/cover.jpg');
    expect(store.list().single.coverUrl, 'https://example.com/cover.jpg');
  });
}
