import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/common.dart';
import '../data/database/database_opener.dart';
import '../data/database/storage_service.dart';
import '../data/database/learning_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../data/database/competency_store.dart';
import '../data/content_service.dart';
import '../services/srs_service.dart';
import '../services/progress_service.dart';
import '../services/lesson_agent_service.dart';
import '../services/pilot_access_service.dart';
import '../widgets/floating_notetaker.dart';

final databaseProvider = Provider<CommonDatabase>((ref) {
  throw UnimplementedError('Must be overridden at startup');
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(databaseProvider));
});

final learningStoreProvider = Provider<LearningStore>((ref) {
  return LearningStore(ref.watch(databaseProvider));
});

final pilotInfrastructureStoreProvider = Provider<PilotInfrastructureStore>((
  ref,
) {
  return PilotInfrastructureStore(ref.watch(databaseProvider));
});

final competencyStoreProvider = Provider<CompetencyStore>((ref) {
  return CompetencyStore(ref.watch(databaseProvider));
});

final pilotAccessServiceProvider = Provider<PilotAccessService>((ref) {
  return PilotAccessService(
    store: ref.watch(learningStoreProvider),
    infrastructure: ref.watch(pilotInfrastructureStoreProvider),
  );
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

Future<CommonDatabase> openAppDatabase() => openDatabase();
