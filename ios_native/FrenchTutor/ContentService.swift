import Foundation

/// Loads and caches the bundled curriculum content (Content/*.json).
final class ContentService {
    static let shared = ContentService()
    private init() {}

    private var vocabCache: [Int: VocabPhase] = [:]
    private var vocabExamplesCache: [String: LessonAgentService.VocabExample]?
    private var grammarCache: GrammarPack?
    private var connectorsCache: ConnectorsPack?
    private var listeningCache: ListeningPack?
    private var writingCache: WritingPack?
    private var roadmapCache: Roadmap?
    private var resourcesCache: ResourcePack?
    private let lock = NSLock()

    // MARK: - Accessors

    func vocabPhase(_ phase: Int) -> VocabPhase? {
        lock.lock(); defer { lock.unlock() }
        if let cached = vocabCache[phase] { return cached }
        guard let loaded: VocabPhase = load("vocab_phase\(phase)") else { return nil }
        vocabCache[phase] = loaded
        return loaded
    }

    var vocabPhases: [VocabPhase] {
        [1, 2, 3].compactMap { vocabPhase($0) }
    }

    /// Every vocab word's example sentence, pre-authored once offline for the whole ~1400-word
    /// bank (Content/vocab_examples.json, keyed by word id) — not generated live by an LLM at
    /// session time. Missing entries (a handful of words a generation pass couldn't cover) are
    /// simply omitted; callers treat a missing example as "no example this session," not an error.
    func vocabExamples(for words: [VocabEntry]) -> [String: LessonAgentService.VocabExample] {
        lock.lock()
        if vocabExamplesCache == nil {
            vocabExamplesCache = load("vocab_examples") ?? [:]
        }
        let all = vocabExamplesCache ?? [:]
        lock.unlock()
        let ids = Set(words.map { $0.id })
        return all.filter { ids.contains($0.key) }
    }

    func grammar() -> GrammarPack? {
        lock.lock(); defer { lock.unlock() }
        if grammarCache == nil { grammarCache = load("grammar") }
        return grammarCache
    }

    func connectors() -> ConnectorsPack? {
        lock.lock(); defer { lock.unlock() }
        if connectorsCache == nil { connectorsCache = load("connectors") }
        return connectorsCache
    }

    func listening() -> ListeningPack? {
        lock.lock(); defer { lock.unlock() }
        if listeningCache == nil { listeningCache = load("listening") }
        return listeningCache
    }

    func writingTasks() -> WritingPack? {
        lock.lock(); defer { lock.unlock() }
        if writingCache == nil { writingCache = load("writing_tasks") }
        return writingCache
    }

    func roadmap() -> Roadmap? {
        lock.lock(); defer { lock.unlock() }
        if roadmapCache == nil { roadmapCache = load("roadmap") }
        return roadmapCache
    }

    func resources() -> ResourcePack? {
        lock.lock(); defer { lock.unlock() }
        if resourcesCache == nil { resourcesCache = load("resources") }
        return resourcesCache
    }

    // MARK: - Lesson context builders (shared by OpenRouter agent and Marie)

    func lessonContext(grammarLesson lesson: GrammarLesson) -> String {
        var parts: [String] = []
        parts.append("LESSON: \(lesson.title) (\(lesson.subtitle))")
        parts.append("USAGE: " + lesson.usage.joined(separator: " "))
        for conj in lesson.conjugations {
            let rows = conj.rows.map { "\($0.pronoun) \($0.form)" }.joined(separator: ", ")
            parts.append("CONJUGATION \(conj.verb) (\(conj.group)): \(rows)")
        }
        let examples = lesson.examples.map { "\($0.fr) = \($0.en)" }.joined(separator: " | ")
        parts.append("EXAMPLES: \(examples)")
        return parts.joined(separator: "\n")
    }

    func lessonContext(topic: GrammarTopic) -> String {
        var parts: [String] = ["LESSON: \(topic.title)"]
        for section in topic.sections {
            let examples = section.examples.map { "\($0.fr) = \($0.en)" }.joined(separator: " | ")
            parts.append("\(section.heading): \(section.body) Examples: \(examples)")
        }
        return parts.joined(separator: "\n")
    }

    func lessonContext(connectorCategory category: String? = nil) -> String {
        guard let pack = connectors() else { return "" }
        let items = category.map { cat in pack.connectors.filter { $0.category == cat } } ?? pack.connectors
        let lines = items.map { "\($0.fr) = \($0.en). Ex: \($0.example.fr)" }
        return "LESSON: French connectors (articulateurs logiques)\n" + lines.joined(separator: "\n")
    }

    func lessonContext(vocabTheme theme: VocabTheme, phase: Int) -> String {
        let lines = theme.entries.map { "\($0.fr) = \($0.en)" }
        return "LESSON: Vocabulary — \(theme.title) (phase \(phase))\n" + lines.joined(separator: ", ")
    }

    /// For a flat cross-theme word list (e.g. the Daily Pathway's mixed SRS queue), unlike
    /// `lessonContext(vocabTheme:)` which needs a single theme.
    func lessonContext(vocabEntries entries: [VocabEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let lines = entries.map { "\($0.fr) = \($0.en)" }
        return "TODAY'S VOCABULARY LIST (\(entries.count) words):\n" + lines.joined(separator: ", ")
    }

    func lessonContext(writingTask task: WritingTask) -> String {
        var parts = ["WRITING TASK: \(task.title) (\(task.type))", "PROMPT: \(task.promptFr)"]
        if !task.targetConnectors.isEmpty {
            let names = connectorFrenchNames(ids: task.targetConnectors)
            parts.append("TARGET CONNECTORS: \(names.joined(separator: ", "))")
        }
        parts.append("HINTS: " + task.rubricHints.joined(separator: " "))
        return parts.joined(separator: "\n")
    }

    func lessonContext(listeningExercise ex: ListeningExercise) -> String {
        "LISTENING EXERCISE: \(ex.title)\nSCRIPT: \(ex.script)"
    }

    func lessonContext(speakingTopic topic: SpeakingTopic) -> String {
        "SPEAKING TOPIC: \(topic.title)\nPROMPT: \(topic.promptFr)\nUSEFUL PHRASES: \(topic.hints.joined(separator: " · "))"
    }

    func connectorFrenchNames(ids: [String]) -> [String] {
        guard let pack = connectors() else { return ids }
        return ids.map { id in pack.connectors.first(where: { $0.id == id })?.fr ?? id }
    }

    // MARK: - Loading

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Content")
            ?? Bundle.main.url(forResource: name, withExtension: "json") else {
            print("ContentService: \(name).json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("ContentService: failed to decode \(name).json — \(error)")
            return nil
        }
    }

    #if DEBUG
    /// Called at launch in debug builds so schema mistakes fail loudly.
    func assertAllContentDecodes() {
        var missing: [String] = []
        if grammar() == nil { missing.append("grammar") }
        if connectors() == nil { missing.append("connectors") }
        if listening() == nil { missing.append("listening") }
        if writingTasks() == nil { missing.append("writing_tasks") }
        if roadmap() == nil { missing.append("roadmap") }
        if resources() == nil { missing.append("resources") }
        for phase in 1...3 where vocabPhase(phase) == nil { missing.append("vocab_phase\(phase)") }
        if !missing.isEmpty {
            print("⚠️ ContentService: failed to load: \(missing.joined(separator: ", "))")
        }
    }
    #endif
}
