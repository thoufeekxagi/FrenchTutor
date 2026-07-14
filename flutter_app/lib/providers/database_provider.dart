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
import '../widgets/floating_notetaker.dart';

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

/// One shared instance app-wide — mirrors iOS's `NotetakerState.shared`. Every
/// `FloatingNotetakerOverlay` mount (tab-bar root, each full-screen lesson/pathway/call
/// screen) must bind to this SAME provider so drag position, draft text, and the on/off
/// toggle stay in sync no matter which layer is on screen. A `Provider` (not
/// `ChangeNotifierProvider`) is used deliberately: `NotetakerState` is a `ChangeNotifier`
/// consumed directly by `ListenableBuilder`/`AnimatedBuilder`-style listeners inside
/// `FloatingNotetakerOverlay` itself, not by watching this provider for rebuilds.
final notetakerStateProvider = Provider<NotetakerState>((ref) {
  return NotetakerState(storage: ref.watch(storageServiceProvider));
});

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}${Platform.pathSeparator}french_tutor.db';
  return sqlite3.open(path);
}
