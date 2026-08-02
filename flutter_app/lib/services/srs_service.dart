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

  /// How many words the Daily Path's "Auto"/"Recommended" vocab queue shows
  /// per practice — separate from [newCardsPerDay], which only governs the
  /// standalone Flashcards lab. Was previously NOT user-facing at all: the
  /// total was silently derived from the session-length setting (standard =
  /// 10, fixed), which read as "stuck on the same 10 words" to a learner
  /// practicing more than once a day. Default 5, adjustable 1-10 in Settings.
  static Future<int> get autoQueueSize async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt('vocab_auto_queue_size') ?? 0;
    return value > 0 ? value.clamp(1, 10) : 5;
  }

  static Future<void> setAutoQueueSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vocab_auto_queue_size', value.clamp(1, 10));
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
        state.intervalDays = state.reps == 0
            ? 1
            : (state.intervalDays * 1.2).clamp(1, double.infinity);
        state.ease = (state.ease - 0.15).clamp(1.3, double.infinity);
        state.reps += 1;
        state.dueAt = now.add(
          Duration(seconds: (state.intervalDays * 86400).round()),
        );
      case SRSGrade.good:
        if (state.reps == 0) {
          state.intervalDays = 1;
        } else if (state.reps == 1) {
          state.intervalDays = 3;
        } else {
          state.intervalDays = state.intervalDays * state.ease;
        }
        state.reps += 1;
        state.dueAt = now.add(
          Duration(seconds: (state.intervalDays * 86400).round()),
        );
      case SRSGrade.easy:
        state.intervalDays =
            (state.intervalDays < 1 ? 1 : state.intervalDays) *
            state.ease *
            1.3;
        state.ease += 0.05;
        state.reps += 1;
        state.dueAt = now.add(
          Duration(seconds: (state.intervalDays * 86400).round()),
        );
    }

    state.lastGrade = grade;
    state.lastReviewedAt = now;
    state.introducedOn ??= store.dayString(now);
    store.upsertSRS(state);
    store.logReview(
      entryId: entryId,
      grade: grade,
      responseType: responseType,
      sessionId: sessionId,
    );
    return state;
  }

  Future<List<VocabEntry>> buildQueue({
    required int phase,
    String? themeId,
    int limit = 40,
  }) async {
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
    return phaseContent.themes
        .firstWhere(
          (t) => t.id == themeId,
          orElse: () => VocabTheme(id: '', title: '', entries: []),
        )
        .entries;
  }

  /// The single queue policy for the guided Daily Path (PILOT_PLAN.md P0.6/P0.7):
  /// budgets come from the learner's session-length preference, not a raw
  /// card-count setting, and are deliberately humane — an agent-led session
  /// costs several spoken passes per word. Labs stay uncapped via buildQueue.
  static ({int newBudget, int reviewBudget, int totalCap}) policyFor(
    String sessionLength, {
    required bool firstEverSession,
  }) {
    final base = switch (sessionLength) {
      'quick' => (newBudget: 2, reviewBudget: 5, totalCap: 7),
      'deep' => (newBudget: 6, reviewBudget: 12, totalCap: 16),
      _ => (newBudget: 4, reviewBudget: 8, totalCap: 10), // standard
    };
    // Day one: three words, one small win — never a flood.
    if (firstEverSession) {
      return (
        newBudget: 3.clamp(0, base.newBudget),
        reviewBudget: base.reviewBudget,
        totalCap: base.totalCap,
      );
    }
    return base;
  }

  /// Returns a CANDIDATE POOL, deliberately bigger than what actually gets
  /// practiced — the caller (see `vocab_picker_screen.dart._beginSession`)
  /// hands this whole pool to `LessonAgentService.planVocabSession` to
  /// genuinely CURATE the final `autoQueueSize` selection, or falls back to
  /// taking the front of this list if that call fails. Both due and unseen
  /// entries are shuffled before picking, which was the root cause of "same
  /// five words every time": the old version always walked the vocab bank
  /// in fixed curriculum order and took the first N, so both the direct
  /// result AND the AI-reorder fallback landed on an identical deterministic
  /// slice call after call. Shuffling here means even a total AI failure now
  /// produces a different, genuinely varied set each time.
  Future<List<VocabEntry>> dailyMixedQueue() async {
    final allEntries = ContentService.shared.vocabPhases
        .expand((p) => p.themes.expand((t) => t.entries))
        .toList();
    final states = store.allSRSStates();
    final now = DateTime.now();
    final basePolicy = policyFor(
      store.profile().sessionLength,
      firstEverSession: store.hasNoReviewHistory(),
    );

    // The learner's own word-count preference is the real cap now, not the
    // session-length-derived total — [autoQueueSize] scales the new/review
    // split proportionally so a 5-word session isn't suddenly all-new or
    // all-review, it's just a smaller version of the same mix.
    final targetSize = await autoQueueSize;
    final scale = basePolicy.totalCap == 0
        ? 1.0
        : targetSize / basePolicy.totalCap;
    final policy = (
      newBudget: (basePolicy.newBudget * scale).round().clamp(0, targetSize),
      reviewBudget: (basePolicy.reviewBudget * scale).round().clamp(
        0,
        targetSize,
      ),
      totalCap: targetSize,
    );

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
    due.shuffle();
    unseen.shuffle();

    // Pool budgets are a multiple of the pacing budgets, not equal to them —
    // this is what actually gives the curator (or the shuffle fallback)
    // something to choose FROM, instead of handing over exactly the words
    // that will be shown.
    const poolMultiplier = 4;
    final newBudget = (policy.newBudget - store.newEntriesIntroducedToday())
        .clamp(0, policy.newBudget);
    final queue = [
      ...due.take(policy.reviewBudget * poolMultiplier),
      ...unseen.take(newBudget * poolMultiplier),
    ];
    final poolCap = targetSize * poolMultiplier;
    final capped = queue.take(poolCap).toList();
    if (capped.length >= targetSize) return capped;

    // Under the target — the daily new-word cap already got used up
    // elsewhere today, but there's no reason to leave the learner staring
    // at "0 words ready" when unseen words still exist in the bank. Top up
    // with more unseen words beyond today's cap (still fresh content, just
    // past today's pacing budget), then with known words for review, until
    // the target is hit or the whole bank is truly spent.
    final chosenIds = capped.map((e) => e.id).toSet();
    final topUp = [...capped];
    for (final entry in unseen) {
      if (topUp.length >= poolCap) break;
      if (chosenIds.add(entry.id)) topUp.add(entry);
    }
    if (topUp.length < targetSize) {
      for (final entry in knownSample(limit: poolCap)) {
        if (topUp.length >= poolCap) break;
        if (chosenIds.add(entry.id)) topUp.add(entry);
      }
    }
    return topUp;
  }

  List<VocabEntry> knownSample({int limit = 6}) {
    final allEntries = ContentService.shared.vocabPhases
        .expand((p) => p.themes.expand((t) => t.entries))
        .toList();
    final states = store.allSRSStates();
    final knownIds = states.entries
        .where((e) => e.value.reps >= 2)
        .map((e) => e.key)
        .toSet();
    final knownEntries = allEntries
        .where((e) => knownIds.contains(e.id))
        .toList();
    knownEntries.shuffle();
    return knownEntries.take(limit).toList();
  }

  ({int due, int unseen, int known}) counts({
    required int phase,
    String? themeId,
  }) {
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
