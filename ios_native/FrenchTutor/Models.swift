import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date

    var isUser: Bool { role == "user" }
    var isTutor: Bool { role == "assistant" || role == "tutor" }
}

struct Session: Identifiable {
    let id: String
    let startedAt: String
    var endedAt: String?
    var summary: String?
    var topic: String?
    var vocabulary: [String]
    // Which Daily Pathway stage this session was — "vocab", "grammar", "reading_listening",
    // "writing", "speaking", or nil for an unstructured "Just talk to Marie" call. Lets Recent
    // Sessions show what kind of session it was, and lets the grammar stage look up the most
    // recent vocab session's transcript to build practice off of.
    var stage: String?
}

/// A note captured via the floating notetaker overlay while working through a lesson.
struct Note: Identifiable {
    let id: Int64
    var tag: String?
    var text: String
    var createdAt: String
    var updatedAt: String
    var timesShown: Int
}
