import 'package:shared_preferences/shared_preferences.dart';
import '../data/content_service.dart';
import '../data/database/learning_store.dart';
import '../models/content_models.dart';
import '../models/srs_state.dart';

class SRSService {
  SRSService({required this.store});

  final LearningStore store;

  static Future<int> get newCardsPerDay async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('srs_new_cards_per_day') ?? 0;
    return value > 0 ? value : 20;
  }

  SRSState grade({
    required String entryId,
    required SRSGrade grade,
    SRSResponseType responseType = SRSResponseType.auto,
    String? sessionId,
  }) {
    var state = store.srsState(entryId) ?? SRSState(entryId: entryId);
    final now = DateTime.now();

    switch (grade) {
      case SRSGrade.again:
        state.reps = 0;
        state.intervalDays = 0;
        state.ease = (state.ease - 0.2).clamp(1.3, double.infinity);
        state.dueAt = now.add(const Duration(minutes: 10));
      case SRSGrade.hard:
        // Correct but effortful (e.g. needed a hint): shorter interval than
        // good, slight ease penalty, but still progress — never a reset.
        state.intervalDays = state.reps == 0 ? 1 : (state.intervalDays * 1.2).clamp(1, double.infinity);
        state.ease = (state.ease - 0.15).clamp(1.3, double.infinity);
        state.reps += 1;
        state.dueAt = now.add(Duration(seconds: (state.intervalDays * 86400).round()));
      case SRSGrade.good:
        if (state.reps == 0) {
          state.intervalDays = 1;
        } else if (state.reps == 1) {
          state.intervalDays = 3;
        } else {
          state.intervalDays = state.intervalDays * state.ease;
        }
        state.reps += 1;
        state.dueAt = now.add(Duration(seconds: (state.intervalDays * 86400).round()));
      case SRSGrade.easy:
        state.intervalDays = (state.intervalDays < 1 ? 1 : state.intervalDays) * state.ease * 1.3;
        state.ease += 0.05;
        state.reps += 1;
        state.dueAt = now.add(Duration(seconds: (state.intervalDays * 86400).round()));
    }

    state.lastGrade = grade;
    state.lastReviewedAt = now;
    state.introducedOn ??= store.dayString(now);
    store.upsertSRS(state);
    store.logReview(entryId: entryId, grade: grade, responseType: responseType, sessionId: sessionId);
    return state;
  }

  Future<List<VocabEntry>> buildQueue({required int phase, String? themeId, int limit = 40}) async {
    final phaseContent = ContentService.shared.vocabPhase(phase);
    if (phaseContent == null) return [];

    final themes = themeId != null
        ? phaseContent.themes.where((t) => t.id == themeId).toList()
        : phaseContent.themes;
    final entries = themes.expand((t) => t.entries).toList();
    final states = store.allSRSStates();
    final now = DateTime.now();

    final due = <VocabEntry>[];
    final unseen = <VocabEntry>[];
    for (final entry in entries) {
      final state = states[entry.id];
      if (state != null) {
        if (state.dueAt != null && state.dueAt!.isBefore(now)) {
          due.add(entry);
        }
      } else {
        unseen.add(entry);
      }
    }

    final cap = await newCardsPerDay;
    final newBudget = (cap - store.newEntriesIntroducedToday()).clamp(0, cap);
    final queue = [...due, ...unseen.take(newBudget)];
    return queue.take(limit).toList();
  }

  List<VocabEntry> allEntries({required int phase, required String themeId}) {
    final phaseContent = ContentService.shared.vocabPhase(phase);
    if (phaseContent == null) return [];
    return phaseContent.themes.firstWhere((t) => t.id == themeId, orElse: () => VocabTheme(id: '', title: '', entries: [])).entries;
  }

  Future<List<VocabEntry>> dailyMixedQueue({int newCap = 25, int limit = 60}) async {
    final allEntries = ContentService.shared.vocabPhases.expand((p) => p.themes.expand((t) => t.entries)).toList();
    final states = store.allSRSStates();
    final now = DateTime.now();

    final due = <VocabEntry>[];
    final unseen = <VocabEntry>[];
    for (final entry in allEntries) {
      final state = states[entry.id];
      if (state != null) {
        if (state.dueAt != null && state.dueAt!.isBefore(now)) due.add(entry);
      } else {
        unseen.add(entry);
      }
    }

    final newBudget = (newCap - store.newEntriesIntroducedToday()).clamp(0, newCap);
    final queue = [...due, ...unseen.take(newBudget)];
    return queue.take(limit).toList();
  }

  List<VocabEntry> knownSample({int limit = 6}) {
    final allEntries = ContentService.shared.vocabPhases.expand((p) => p.themes.expand((t) => t.entries)).toList();
    final states = store.allSRSStates();
    final knownIds = states.entries.where((e) => e.value.reps >= 2).map((e) => e.key).toSet();
    final knownEntries = allEntries.where((e) => knownIds.contains(e.id)).toList();
    knownEntries.shuffle();
    return knownEntries.take(limit).toList();
  }

  ({int due, int unseen, int known}) counts({required int phase, String? themeId}) {
    final phaseContent = ContentService.shared.vocabPhase(phase);
    if (phaseContent == null) return (due: 0, unseen: 0, known: 0);

    final themes = themeId != null
        ? phaseContent.themes.where((t) => t.id == themeId).toList()
        : phaseContent.themes;
    final entries = themes.expand((t) => t.entries).toList();
    final states = store.allSRSStates();
    final now = DateTime.now();

    var due = 0, unseen = 0, known = 0;
    for (final entry in entries) {
      final state = states[entry.id];
      if (state != null) {
        if (state.reps >= 3 && state.intervalDays >= 21) known++;
        if (state.dueAt != null && state.dueAt!.isBefore(now)) due++;
      } else {
        unseen++;
      }
    }
    return (due: due, unseen: unseen, known: known);
  }
}
