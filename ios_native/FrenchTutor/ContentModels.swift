import Foundation

// MARK: - Vocabulary

struct VocabPhase: Codable {
    let phase: Int
    let title: String
    let themes: [VocabTheme]

    var totalEntries: Int { themes.reduce(0) { $0 + $1.entries.count } }
}

struct VocabTheme: Codable, Identifiable {
    let id: String
    let title: String
    let entries: [VocabEntry]
}

struct VocabEntry: Codable, Identifiable {
    let id: String
    let en: String
    let fr: String
    let phonetic: String
}

// MARK: - Grammar

struct GrammarPack: Codable {
    let lessons: [GrammarLesson]
    let irregularVerbs: [IrregularVerb]
    let topics: [GrammarTopic]
}

struct GrammarLesson: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let order: Int
    let usage: [String]
    let narration: [String]
    let conjugations: [Conjugation]
    let examples: [BilingualExample]
    let drills: [Drill]
}

struct Conjugation: Codable, Identifiable {
    let verb: String
    let group: String
    let rows: [ConjRow]
    var id: String { verb }
}

struct ConjRow: Codable, Identifiable {
    let pronoun: String
    let form: String
    var id: String { pronoun }
}

struct BilingualExample: Codable, Identifiable {
    let fr: String
    let en: String
    var id: String { fr }
}

struct Drill: Codable, Identifiable {
    let type: String
    let prompt: String
    let answer: String
    let choices: [String]
    var id: String { prompt }
}

struct IrregularVerb: Codable, Identifiable {
    let verb: String
    let en: String
    let present: [String]
    let passeCompose: String
    let examples: [BilingualExample]
    var id: String { verb }
}

struct GrammarTopic: Codable, Identifiable {
    let id: String
    let title: String
    let narration: [String]
    let sections: [TopicSection]
    let drills: [Drill]
}

struct TopicSection: Codable, Identifiable {
    let heading: String
    let body: String
    let examples: [BilingualExample]
    var id: String { heading }
}

// MARK: - Connectors

struct ConnectorsPack: Codable {
    let tip: String
    let connectors: [Connector]
}

struct Connector: Codable, Identifiable {
    let id: String
    let fr: String
    let en: String
    let category: String
    let core: Bool
    let example: BilingualExample
}

// MARK: - Grammar practice cards (generated)

/// One card in a generated grammar practice session — deliberately shaped just like `VocabEntry`
/// (front/back, one card at a time) instead of the old usage-bullet/conjugation-table/drill
/// layout, so `AgentLedGrammarView` can walk through it exactly the way `AgentLedVocabView` walks
/// through vocab: a short French sentence in the chosen tense on the back, its English meaning on
/// the front, and a one-line grammar note in place of vocab's phonetic hint. Generated ONCE before
/// the session starts (see `LessonAgentService.generateGrammarPracticeCards`), never invented live
/// during teaching, per STRUCTURE.md.
struct GrammarPracticeCard: Codable, Identifiable {
    let id: String
    let fr: String
    let en: String
    let note: String
}

// MARK: - Listening

struct ListeningPack: Codable {
    let exercises: [ListeningExercise]
}

struct ListeningExercise: Codable, Identifiable {
    let id: String
    let title: String
    let phase: Int
    let script: String
    let questions: [MultipleChoiceQuestion]
    let dictation: [String]
}

struct MultipleChoiceQuestion: Codable, Identifiable {
    let q: String
    let choices: [String]
    let answerIndex: Int
    var id: String { q }
}

// MARK: - Reading passage (Daily Pathway stage 2, agent-led word-by-word walkthrough)

/// One word or short phrase within a `ReadingPassage`, taught the same way vocab teaches a
/// single word — meaning, a simple grammar note, a pronunciation tip — but walked through in
/// the order it appears in the passage rather than as an isolated flashcard. Grammar notes are
/// intentionally simple (one sentence, no conjugation tables) for this first version; a
/// harder/dynamic-difficulty version is planned for later once this base pattern is proven.
struct ReadingSegment: Codable, Identifiable {
    let fr: String          // the French word or short phrase
    let en: String          // English meaning
    let grammarNote: String // one simple sentence, English, why this form/word order
    let pronunciationTip: String // one simple sentence, English
    var id: String { fr }
}

/// A short French passage broken into `ReadingSegment`s, built once (either offline-authored from
/// `Content/listening.json` or generated a single time right when the student picks the "from
/// words I just practiced" path) — never live, word-by-word, during the teaching session itself.
struct ReadingPassage: Codable, Identifiable {
    let id: String
    let title: String
    let segments: [ReadingSegment]
    let fullText: String // the whole French text for display
}

// MARK: - Writing

struct WritingPack: Codable {
    let tasks: [WritingTask]
}

struct WritingTask: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let promptFr: String
    let promptEn: String
    let minWords: Int
    let targetConnectors: [String]
    let rubricHints: [String]
}

// MARK: - Roadmap

struct Roadmap: Codable {
    let target: String
    let months: [RoadmapMonth]
    let dailyHabits: [DailyHabit]
    let vocabularyBreakdown: String
}

struct RoadmapMonth: Codable, Identifiable {
    let month: Int
    let title: String
    let goals: [String]
    let grammarChecklist: [String]
    var id: Int { month }
}

struct DailyHabit: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let minutes: Int
    let lab: String
}

// MARK: - Resources

struct ResourcePack: Codable {
    let readingProgression: [ReadingStage]
    let listeningTargets: [ListeningTarget]
    let speakingTopics: [SpeakingTopic]
    let writingGuidance: [String]
    let externalResources: [ExternalResource]
}

struct ReadingStage: Codable, Identifiable {
    let stage: Int
    let title: String
    let detail: String
    var id: Int { stage }
}

struct ListeningTarget: Codable, Identifiable {
    let id: String
    let title: String
    let minutes: Int
    let detail: String
}

struct SpeakingTopic: Codable, Identifiable {
    let id: String
    let title: String
    let promptFr: String
    let hints: [String]
}

struct ExternalResource: Codable, Identifiable {
    let name: String
    let bestFor: String
    let free: Bool
    var id: String { name }
}
