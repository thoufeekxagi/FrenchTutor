import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/common.dart';
import '../data/database/database_opener.dart';
import '../data/database/storage_service.dart';
import '../data/database/learning_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../data/database/competency_store.dart';
import '../data/database/evidence_store.dart';
import '../data/database/competency_state_store.dart';
import '../data/database/generated_scene_cache_store.dart';
import '../data/database/generated_story_store.dart';
import '../data/database/generated_roleplay_store.dart';
import '../data/database/plan_store.dart';
import '../orchestration/runtime/orchestration_service.dart';
import '../data/content_service.dart';
import '../services/srs_service.dart';
import '../services/progress_service.dart';
import '../services/lesson_agent_service.dart';
import '../services/pilot_access_service.dart';
import '../services/subscription_gate_service.dart';
import '../services/sync_service.dart';
import '../widgets/floating_notetaker.dart';

final databaseProvider = Provider<CommonDatabase>((ref) {
  throw UnimplementedError('Must be overridden at startup');
});

/// One shared gateway to Supabase for every store below — every local
/// learning-data write also pushes here (best-effort, never blocking).
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(databaseProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(ref.watch(databaseProvider));
});

final learningStoreProvider = Provider<LearningStore>((ref) {
  return LearningStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final pilotInfrastructureStoreProvider = Provider<PilotInfrastructureStore>((
  ref,
) {
  return PilotInfrastructureStore(ref.watch(databaseProvider));
});

final competencyStoreProvider = Provider<CompetencyStore>((ref) {
  return CompetencyStore(ref.watch(databaseProvider));
});

final evidenceStoreProvider = Provider<EvidenceStore>((ref) {
  return EvidenceStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final competencyStateStoreProvider = Provider<CompetencyStateStore>((ref) {
  return CompetencyStateStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final planStoreProvider = Provider<PlanStore>((ref) {
  return PlanStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final orchestrationServiceProvider = Provider<OrchestrationService>((ref) {
  return const OrchestrationService();
});

final generatedSceneCacheStoreProvider = Provider<GeneratedSceneCacheStore>((
  ref,
) {
  return GeneratedSceneCacheStore(ref.watch(databaseProvider));
});

final generatedStoryStoreProvider = Provider<GeneratedStoryStore>((ref) {
  return GeneratedStoryStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final generatedRoleplayStoreProvider = Provider<GeneratedRoleplayStore>((ref) {
  return GeneratedRoleplayStore(
    ref.watch(databaseProvider),
    ref.watch(syncServiceProvider),
  );
});

final pilotAccessServiceProvider = Provider<PilotAccessService>((ref) {
  return PilotAccessService(
    store: ref.watch(learningStoreProvider),
    infrastructure: ref.watch(pilotInfrastructureStoreProvider),
  );
});

final subscriptionGateServiceProvider = Provider<SubscriptionGateService>((
  ref,
) {
  return SubscriptionGateService(
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
