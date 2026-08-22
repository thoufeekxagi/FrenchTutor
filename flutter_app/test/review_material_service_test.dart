import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/storage_service.dart';
import 'package:french_tutor/models/session.dart';
import 'package:french_tutor/services/review_material_service.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

void main() {
  test('all speaking stage variants appear in recent speaking history', () {
    final storage = StorageService(sqlite3.openInMemory());
    final stages = [
      'speaking_guided',
      'picture_description',
      'pronunciation_repair',
    ];

    for (var index = 0; index < stages.length; index++) {
      final id = 'speaking-$index';
      storage.saveSession(
        Session(
          id: id,
          startedAt: '2026-08-22T09:0$index:00.000Z',
          endedAt: '2026-08-22T09:1$index:00.000Z',
          summary: 'Completed speaking practice.',
          topic: 'Topic $index',
          stage: stages[index],
        ),
      );
      storage.saveMessage(
        sessionId: id,
        role: 'assistant',
        content: 'Bonjour.',
      );
    }

    final recent = ReviewMaterialService.recentSessions(storage);

    expect(recent, hasLength(3));
    expect(recent.map((session) => session.skill), everyElement('Speaking'));
    expect(
      recent.map((session) => session.sessionId),
      containsAll(<String>['speaking-0', 'speaking-1', 'speaking-2']),
    );
    expect(storage.getSessionMessages(sessionId: 'speaking-0'), hasLength(1));
  });
}
