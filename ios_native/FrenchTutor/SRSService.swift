import Foundation

enum SRSGrade: Int {
    case again = 0
    case good = 1
    case easy = 2
}

/// SM-2-lite spaced repetition scheduling on top of LearningStore.
class SRSService {
    private let store: LearningStore

    static var newCardsPerDay: Int {
        let value = UserDefaults.standard.integer(forKey: "srs_new_cards_per_day")
        return value > 0 ? value : 20
    }

    init(store: LearningStore) {
        self.store = store
    }

    /// Apply a grade to an entry and persist the new state.
    @discardableResult
    func grade(entryId: String, grade: SRSGrade) -> SRSState {
        var state = store.srsState(for: entryId) ?? SRSState(entryId: entryId)

        switch grade {
        case .again:
            state.reps = 0
            state.intervalDays = 0
            state.ease = max(1.3, state.ease - 0.2)
            state.dueAt = Date().addingTimeInterval(10 * 60)
        case .good:
            if state.reps == 0 {
                state.intervalDays = 1
            } else if state.reps == 1 {
                state.intervalDays = 3
            } else {
                state.intervalDays = state.intervalDays * state.ease
            }
            state.reps += 1
            state.dueAt = Date().addingTimeInterval(state.intervalDays * 86400)
        case .easy:
            state.intervalDays = max(1, state.intervalDays) * state.ease * 1.3
            state.ease += 0.05
            state.reps += 1
            state.dueAt = Date().addingTimeInterval(state.intervalDays * 86400)
        }

        state.lastGrade = grade.rawValue
        store.upsertSRS(state)
        return state
    }

    /// Build a study queue for a theme (or a whole phase when theme is nil):
    /// all due reviews first, then unseen cards up to the daily new-card cap.
    func buildQueue(phase: Int, themeId: String? = nil, limit: Int = 40) -> [VocabEntry] {
        guard let phaseContent = ContentService.shared.vocabPhase(phase) else { return [] }
        let themes = themeId.map { id in phaseContent.themes.filter { $0.id == id } } ?? phaseContent.themes
        let entries = themes.flatMap { $0.entries }

        let states = store.allSRSStates()
        let now = Date()

        var due: [VocabEntry] = []
        var unseen: [VocabEntry] = []
        for entry in entries {
            if let state = states[entry.id] {
                if let dueAt = state.dueAt, dueAt <= now {
                    due.append(entry)
                }
            } else {
                unseen.append(entry)
            }
        }

        let newBudget = max(0, SRSService.newCardsPerDay - store.newEntriesIntroducedToday())
        let queue = due + unseen.prefix(newBudget)
        return Array(queue.prefix(limit))
    }

    /// All entries in a theme regardless of due date — used for "review anyway" retakes.
    func allEntries(phase: Int, themeId: String) -> [VocabEntry] {
        guard let phaseContent = ContentService.shared.vocabPhase(phase) else { return [] }
        return phaseContent.themes.first(where: { $0.id == themeId })?.entries ?? []
    }

    /// Cross-phase queue for the daily anchor session: every due review across all phases,
    /// plus new words (curriculum order — phase 1 themes first) up to `newCap` for the day.
    func dailyMixedQueue(newCap: Int = 25, limit: Int = 60) -> [VocabEntry] {
        let allEntries = ContentService.shared.vocabPhases.flatMap { phase in phase.themes.flatMap { $0.entries } }
        let states = store.allSRSStates()
        let now = Date()

        var due: [VocabEntry] = []
        var unseen: [VocabEntry] = []
        for entry in allEntries {
            if let state = states[entry.id] {
                if let dueAt = state.dueAt, dueAt <= now { due.append(entry) }
            } else {
                unseen.append(entry)
            }
        }

        let newBudget = max(0, newCap - store.newEntriesIntroducedToday())
        let queue = due + unseen.prefix(newBudget)
        return Array(queue.prefix(limit))
    }

    /// A sample of already-learned words (reps >= 2) across all phases, for a quick recall quiz.
    func knownSample(limit: Int = 6) -> [VocabEntry] {
        let allEntries = ContentService.shared.vocabPhases.flatMap { phase in phase.themes.flatMap { $0.entries } }
        let states = store.allSRSStates()
        let knownIds = Set(states.filter { $0.value.reps >= 2 }.map { $0.key })
        let knownEntries = allEntries.filter { knownIds.contains($0.id) }
        return Array(knownEntries.shuffled().prefix(limit))
    }

    /// Due and unseen counts for badges on deck rows.
    func counts(phase: Int, themeId: String? = nil) -> (due: Int, unseen: Int, known: Int) {
        guard let phaseContent = ContentService.shared.vocabPhase(phase) else { return (0, 0, 0) }
        let themes = themeId.map { id in phaseContent.themes.filter { $0.id == id } } ?? phaseContent.themes
        let entries = themes.flatMap { $0.entries }

        let states = store.allSRSStates()
        let now = Date()
        var due = 0, unseen = 0, known = 0
        for entry in entries {
            if let state = states[entry.id] {
                if state.reps >= 3 && state.intervalDays >= 21 { known += 1 }
                if let dueAt = state.dueAt, dueAt <= now { due += 1 }
            } else {
                unseen += 1
            }
        }
        return (due, unseen, known)
    }
}
