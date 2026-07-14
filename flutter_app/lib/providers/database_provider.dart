import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../data/database/storage_service.dart';
import '../data/database/learning_store.dart';
import '../data/content_service.dart';
import '../services/srs_service.dart';
import '../services/progress_service.dart';
import '../services/lesson_agent_service.dart';

final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('Must be overridden at startup');
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(databaseProvider));
});

final learningStoreProvider = Provider<LearningStore>((ref) {
  return LearningStore(ref.watch(databaseProvider));
});

final contentServiceProvider = Provider<ContentService>((ref) {
  return ContentService.shared;
});

final srsServiceProvider = Provider<SRSService>((ref) {
  return SRSService(store: ref.watch(learningStoreProvider));
});

final progressServiceProvider = Provider<ProgressService>((ref) {
  return ProgressService(store: ref.watch(learningStoreProvider));
});

final lessonAgentServiceProvider = Provider<LessonAgentService>((ref) {
  return LessonAgentService.shared;
});

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}${Platform.pathSeparator}french_tutor.db';
  return sqlite3.open(path);
}
