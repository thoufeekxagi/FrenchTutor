import Foundation

struct SkillProgress {
    let name: String
    let icon: String
    let fraction: Double
    let detail: String
}

/// Aggregates learning data into dashboard/progress numbers.
class ProgressService {
    private let store: LearningStore

    init(store: LearningStore) {
        self.store = store
    }

    /// Consecutive days ending today (or yesterday) with at least one habit done.
    func streak() -> Int {
        let days = Set(store.activeDays())
        guard !days.isEmpty else { return 0 }

        let calendar = Calendar.current
        var count = 0
        var cursor = Date()
        // Allow the streak to survive if today has no activity yet.
        if !days.contains(store.dayString(cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(store.dayString(yesterday)) else { return 0 }
            cursor = yesterday
        }
        while days.contains(store.dayString(cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    func todaysHabits() -> [(habit: DailyHabit, done: Bool, minutes: Int)] {
        guard let roadmap = ContentService.shared.roadmap() else { return [] }
        let state = store.habits(on: Date())
        return roadmap.dailyHabits.map { habit in
            let entry = state[habit.id]
            return (habit, entry?.done ?? false, entry?.minutes ?? 0)
        }
    }

    /// Current roadmap month based on the start date set in Settings (defaults to month 1).
    func currentMonth() -> RoadmapMonth? {
        guard let roadmap = ContentService.shared.roadmap() else { return nil }
        let start = UserDefaults.standard.object(forKey: "roadmap_start_date") as? Date ?? Date()
        let months = Calendar.current.dateComponents([.month], from: start, to: Date()).month ?? 0
        let index = min(max(months, 0), roadmap.months.count - 1)
        return roadmap.months[index]
    }

    func vocabCounts() -> (known: Int, learning: Int, total: Int) {
        let states = store.allSRSStates()
        var known = 0, learning = 0, total = 0
        for phase in ContentService.shared.vocabPhases {
            for theme in phase.themes {
                for entry in theme.entries {
                    total += 1
                    if let state = states[entry.id] {
                        if state.reps >= 3 && state.intervalDays >= 21 {
                            known += 1
                        } else {
                            learning += 1
                        }
                    }
                }
            }
        }
        return (known, learning, total)
    }

    /// Grammar checklist: (lesson/topic id, title, completed).
    func grammarChecklist() -> [(id: String, title: String, done: Bool)] {
        guard let grammar = ContentService.shared.grammar() else { return [] }
        let progress = store.allLessonProgress()
        var items: [(String, String, Bool)] = []
        for lesson in grammar.lessons.sorted(by: { $0.order < $1.order }) {
            items.append((lesson.id, lesson.title, progress[lesson.id]?.status == "completed"))
        }
        for topic in grammar.topics {
            items.append((topic.id, topic.title, progress[topic.id]?.status == "completed"))
        }
        return items
    }

    func skillProgress() -> [SkillProgress] {
        let vocab = vocabCounts()
        let vocabFraction = vocab.total > 0 ? Double(vocab.known) / Double(vocab.total) : 0

        let checklist = grammarChecklist()
        let grammarDone = checklist.filter { $0.done }.count
        let grammarFraction = checklist.isEmpty ? 0 : Double(grammarDone) / Double(checklist.count)

        let progress = store.allLessonProgress()
        let listeningTotal = ContentService.shared.listening()?.exercises.count ?? 0
        let listeningDone = ContentService.shared.listening()?.exercises.filter {
            progress["listening_\($0.id)"]?.status == "completed"
        }.count ?? 0
        let listeningFraction = listeningTotal > 0 ? Double(listeningDone) / Double(listeningTotal) : 0

        let submissions = store.submissions()
        let writingTotal = ContentService.shared.writingTasks()?.tasks.count ?? 0
        let writtenTasks = Set(submissions.map { $0.taskId }).count
        let writingFraction = writingTotal > 0 ? Double(writtenTasks) / Double(writingTotal) : 0

        return [
            SkillProgress(name: "Vocabulary", icon: "rectangle.stack.fill", fraction: vocabFraction,
                          detail: "\(vocab.known) known · \(vocab.learning) learning · \(vocab.total) total"),
            SkillProgress(name: "Grammar", icon: "text.book.closed.fill", fraction: grammarFraction,
                          detail: "\(grammarDone)/\(checklist.count) lessons mastered"),
            SkillProgress(name: "Listening", icon: "headphones", fraction: listeningFraction,
                          detail: "\(listeningDone)/\(listeningTotal) exercises completed"),
            SkillProgress(name: "Writing", icon: "pencil.line", fraction: writingFraction,
                          detail: "\(writtenTasks)/\(writingTotal) tasks attempted"),
        ]
    }

    /// Compact "where the student is" summary, injected into every Marie call and
    /// LessonAgent question so the AI calibrates level/pacing instead of assuming
    /// a fixed beginner starting point every time.
    func learnerProfileSummary() -> String {
        var lines: [String] = []

        if let month = currentMonth() {
            lines.append("Currently on month \(month.month) of a 6-month CLB 7 / TEF-TCF Canada plan: \(month.title).")
        }

        let vocab = vocabCounts()
        if vocab.total > 0 {
            lines.append("Vocabulary: \(vocab.known) words mastered, \(vocab.learning) still being learned, out of \(vocab.total) total across 3 phases.")
        }

        let checklist = grammarChecklist()
        let mastered = checklist.filter { $0.done }.map { $0.title }
        let pending = checklist.filter { !$0.done }.map { $0.title }
        if !mastered.isEmpty {
            lines.append("Grammar already mastered: \(mastered.joined(separator: ", ")).")
        }
        if !pending.isEmpty {
            lines.append("Grammar still being learned: \(pending.joined(separator: ", ")).")
        }

        let quiz = store.lessonStatus("connectors_quiz")
        if quiz.status != "not_started", let score = quiz.score {
            lines.append("Connectors quiz best score: \(Int(score * 100))%.")
        }

        let mistakes = store.topMistakeTags(limit: 3)
        if !mistakes.isEmpty {
            let described = mistakes.map { "\($0.description) (seen \($0.count)x)" }.joined(separator: "; ")
            lines.append("Recurring mistakes to watch for and gently work back in: \(described).")
        }

        let streakDays = streak()
        lines.append(streakDays > 0
            ? "On a \(streakDays)-day study streak — keep the momentum, don't restate the basics."
            : "No active streak right now — a little extra encouragement helps.")

        return lines.joined(separator: " ")
    }

    /// Total speaking minutes derived from stored call sessions.
    func speakingMinutes(sessions: [Session]) -> Int {
        let iso = ISO8601DateFormatter()
        var total: TimeInterval = 0
        for session in sessions {
            guard let start = iso.date(from: session.startedAt),
                  let endString = session.endedAt,
                  let end = iso.date(from: endString) else { continue }
            total += max(0, end.timeIntervalSince(start))
        }
        return Int(total / 60)
    }
}
