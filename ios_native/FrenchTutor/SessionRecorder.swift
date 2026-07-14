import Foundation

/// Records a live stage session's full transcript to `StorageService`, tagged with which Daily
/// Pathway stage it was — "vocab", "grammar", "reading_listening", "writing", "speaking", or nil
/// for an unstructured "Just talk to Marie" call. Used so Recent Sessions shows what kind of
/// session each one was, and so the Grammar stage can pull the transcript of the Vocab session
/// that just happened (via `StorageService.mostRecentSession(stage:)` + `messages(for:)`) to build
/// today's grammar practice around, instead of teaching in a vacuum.
final class SessionRecorder {
    private let storage = StorageService()
    let sessionId = UUID().uuidString
    private let stage: String
    private let topic: String
    private let startedAt: String

    init(stage: String, topic: String) {
        self.stage = stage
        self.topic = topic
        self.startedAt = ISO8601DateFormatter().string(from: Date())
    }

    func logUser(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.saveMessage(sessionId: sessionId, role: "user", content: trimmed)
    }

    func logTutor(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.saveMessage(sessionId: sessionId, role: "assistant", content: trimmed)
    }

    /// Call once, when the stage session ends. `summary` shows in Recent Sessions' row subtitle.
    func finish(summary: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        storage.saveSession(Session(id: sessionId, startedAt: startedAt, endedAt: now, summary: summary, topic: topic, vocabulary: [], stage: stage))
    }

    /// ONE short representative line from the most recent Vocab session's transcript — not the
    /// whole thing. Grammar generation only needs a hint of what the student was just doing, not
    /// a full transcript dump; sending the whole session history bloated the request and slowed
    /// the LLM call down for no real benefit. Picks the last substantial thing the student said
    /// (skipping bare nav words like "next"/"again"), truncated hard. Empty string if there's no
    /// prior vocab session — callers should treat that as "no context available", not an error.
    static func recentVocabTranscript(maxCharacters: Int = 120) -> String {
        let storage = StorageService()
        guard let session = storage.mostRecentSession(stage: "vocab") else { return "" }
        let turns = storage.getSessionMessages(sessionId: session.id)
        let navWords: Set<String> = ["next", "again", "back", "yes", "yeah", "ok", "okay", "oui", "d'accord"]
        let lastSubstantial = turns.last { turn in
            turn.role == "user" && turn.content.split(separator: " ").count > 1
                && !navWords.contains(turn.content.trimmingCharacters(in: .whitespaces).lowercased())
        }
        let line = lastSubstantial?.content ?? turns.last(where: { $0.role == "user" })?.content ?? ""
        return String(line.prefix(maxCharacters))
    }
}
