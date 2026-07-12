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
}
