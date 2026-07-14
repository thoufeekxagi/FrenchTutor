import '../data/content_service.dart';
import '../data/database/learning_store.dart';
import '../models/content_models.dart';
import '../models/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SkillProgress {
  SkillProgress({required this.name, required this.icon, required this.fraction, required this.detail});
  final String name;
  final String icon;
  final double fraction;
  final String detail;
}

class ProgressService {
  ProgressService({required this.store});

  final LearningStore store;

  int streak() {
    final days = store.activeDays().toSet();
    if (days.isEmpty) return 0;

    var count = 0;
    var cursor = DateTime.now();
    if (!days.contains(store.dayString(cursor))) {
      final yesterday = cursor.subtract(const Duration(days: 1));
      if (!days.contains(store.dayString(yesterday))) return 0;
      cursor = yesterday;
    }
    while (days.contains(store.dayString(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  List<({DailyHabit habit, bool done, int minutes})> todaysHabits() {
    final roadmap = ContentService.shared.roadmap();
    if (roadmap == null) return [];
    final state = store.habits();
    return roadmap.dailyHabits.map((habit) {
      final entry = state[habit.id];
      return (habit: habit, done: entry?.done ?? false, minutes: entry?.minutes ?? 0);
    }).toList();
  }

  Future<RoadmapMonth?> currentMonth() async {
    final roadmap = ContentService.shared.roadmap();
    if (roadmap == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt('roadmap_start_date');
    final start = startMs != null ? DateTime.fromMillisecondsSinceEpoch(startMs) : DateTime.now();
    final months = DateTime.now().difference(start).inDays ~/ 30;
    final index = months.clamp(0, roadmap.months.length - 1);
    return roadmap.months[index];
  }

  ({int known, int learning, int total}) vocabCounts() {
    final states = store.allSRSStates();
    var known = 0, learning = 0, total = 0;
    for (final phase in ContentService.shared.vocabPhases) {
      for (final theme in phase.themes) {
        for (final entry in theme.entries) {
          total++;
          final state = states[entry.id];
          if (state != null) {
            if (state.reps >= 3 && state.intervalDays >= 21) {
              known++;
            } else {
              learning++;
            }
          }
        }
      }
    }
    return (known: known, learning: learning, total: total);
  }

  List<({String id, String title, bool done})> grammarChecklist() {
    final grammar = ContentService.shared.grammar();
    if (grammar == null) return [];
    final progress = store.allLessonProgress();
    final items = <({String id, String title, bool done})>[];
    for (final lesson in grammar.lessons.toList()..sort((a, b) => a.order.compareTo(b.order))) {
      items.add((id: lesson.id, title: lesson.title, done: progress[lesson.id]?.status == 'completed'));
    }
    for (final topic in grammar.topics) {
      items.add((id: topic.id, title: topic.title, done: progress[topic.id]?.status == 'completed'));
    }
    return items;
  }

  List<SkillProgress> skillProgress() {
    final vocab = vocabCounts();
    final vocabFraction = vocab.total > 0 ? vocab.known / vocab.total : 0.0;

    final checklist = grammarChecklist();
    final grammarDone = checklist.where((c) => c.done).length;
    final grammarFraction = checklist.isEmpty ? 0.0 : grammarDone / checklist.length;

    final progress = store.allLessonProgress();
    final listeningExercises = ContentService.shared.listening()?.exercises ?? [];
    final listeningTotal = listeningExercises.length;
    final listeningDone = listeningExercises.where((e) => progress['listening_${e.id}']?.status == 'completed').length;
    final listeningFraction = listeningTotal > 0 ? listeningDone / listeningTotal : 0.0;

    final submissions = store.submissions();
    final writingTotal = ContentService.shared.writingTasks()?.tasks.length ?? 0;
    final writtenTasks = submissions.map((s) => s.taskId).toSet().length;
    final writingFraction = writingTotal > 0 ? writtenTasks / writingTotal : 0.0;

    return [
      SkillProgress(name: 'Vocabulary', icon: 'rectangle.stack.fill', fraction: vocabFraction, detail: '${vocab.known} known · ${vocab.learning} learning · ${vocab.total} total'),
      SkillProgress(name: 'Grammar', icon: 'text.book.closed.fill', fraction: grammarFraction, detail: '$grammarDone/${checklist.length} lessons mastered'),
      SkillProgress(name: 'Listening', icon: 'headphones', fraction: listeningFraction, detail: '$listeningDone/$listeningTotal exercises completed'),
      SkillProgress(name: 'Writing', icon: 'pencil.line', fraction: writingFraction, detail: '$writtenTasks/$writingTotal tasks attempted'),
    ];
  }

  Future<String> learnerProfileSummary() async {
    final lines = <String>[];

    final month = await currentMonth();
    if (month != null) {
      lines.add("Currently on month ${month.month} of a 6-month CLB 7 / TEF-TCF Canada plan: ${month.title}.");
    }

    final vocab = vocabCounts();
    if (vocab.total > 0) {
      lines.add("Vocabulary: ${vocab.known} words mastered, ${vocab.learning} still being learned, out of ${vocab.total} total across 3 phases.");
    }

    final checklist = grammarChecklist();
    final mastered = checklist.where((c) => c.done).map((c) => c.title).toList();
    final pending = checklist.where((c) => !c.done).map((c) => c.title).toList();
    if (mastered.isNotEmpty) {
      lines.add("Grammar already mastered: ${mastered.join(', ')}.");
    }
    if (pending.isNotEmpty) {
      lines.add("Grammar still being learned: ${pending.join(', ')}.");
    }

    final quiz = store.lessonStatus('connectors_quiz');
    if (quiz.status != 'not_started' && quiz.score != null) {
      lines.add("Connectors quiz best score: ${(quiz.score! * 100).round()}%.");
    }

    final mistakes = store.topMistakeTags(limit: 3);
    if (mistakes.isNotEmpty) {
      final described = mistakes.map((m) => '${m.description} (seen ${m.count}x)').join('; ');
      lines.add("Recurring mistakes to watch for and gently work back in: $described.");
    }

    final streakDays = streak();
    lines.add(streakDays > 0
        ? "On a $streakDays-day study streak — keep the momentum, don't restate the basics."
        : "No active streak right now — a little extra encouragement helps.");

    return lines.join(' ');
  }

  int speakingMinutes(List<Session> sessions) {
    var total = 0.0;
    for (final session in sessions) {
      final start = DateTime.tryParse(session.startedAt);
      final end = session.endedAt != null ? DateTime.tryParse(session.endedAt!) : null;
      if (start != null && end != null) {
        total += end.difference(start).inSeconds.clamp(0, double.maxFinite.toInt());
      }
    }
    return total ~/ 60;
  }
}
