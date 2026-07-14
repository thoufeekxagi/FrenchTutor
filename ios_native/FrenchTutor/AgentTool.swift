import Foundation

/// A Gemini Live function declaration. `parameters` uses Gemini's own OpenAPI-subset
/// schema casing ("OBJECT"/"STRING"/"INTEGER"/"BOOLEAN"/"ARRAY"), not lowercase JSON Schema.
struct AgentTool {
    let name: String
    let description: String
    let parameters: [String: Any]

    var declaration: [String: Any] {
        ["name": name, "description": description, "parameters": parameters]
    }

    private static func object(_ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["type": "OBJECT", "properties": properties, "required": required]
    }

    private static func stringEnum(_ description: String, values: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "STRING", "description": description]
        if let values { schema["enum"] = values }
        return schema
    }

    /// Vocab-only session (Daily Pathway stage 1). Deliberately just ONE tool. Navigation
    /// (advancing, going back) used to be tools she could call on her own initiative
    /// (next_card/previous_card) — that gave her de facto control over pacing, and testing
    /// showed she'd frequently decide to move on the instant a single attempt happened, far
    /// faster than the student wanted, or narrate as if she'd moved on without ever actually
    /// calling the tool. Navigation is now driven ENTIRELY by the app: it watches the
    /// student's own transcript for explicit intent ("next", "go back", etc.) and by direct UI
    /// buttons, and moves the card the instant either happens — no model involved in that
    /// decision at all, deterministic on a fresh install with no tuning required. She's told
    /// the current word via a context note whenever it changes and just reacts to it. Grading
    /// judgment is still useful from her (catching a bad pronunciation attempt), so mark_result
    /// stays as her one remaining tool.
    static let vocabPalette: [AgentTool] = [
        AgentTool(
            name: "mark_result",
            description: "Propose a grade for how well the student did with the current word. The app will only accept this if the student has actually attempted the word.",
            parameters: object(["grade": stringEnum("How well the student recalled/pronounced the word.", values: ["again", "good", "easy"])], required: ["grade"])
        ),
    ]

    /// Reading & Listening session (Daily Pathway stage 2), rebuilt against the same rule as
    /// `vocabPalette`: navigation through the passage's segments is decided entirely by the app
    /// (watching the student's transcript / button taps), never by a model tool call. The old
    /// version gave the model show_conjugation/ask_drill/show_question as tools it fired on its
    /// own judgment — same pacing/desync problems as vocab had before the fix. Only one
    /// judgment-only tool remains, mirroring vocab's mark_result.
    static let readingPalette: [AgentTool] = [
        AgentTool(
            name: "mark_segment_result",
            description: "Propose a grade for how well the student did with the current word/phrase segment. The app will only accept this if the student has actually attempted it.",
            parameters: object(["grade": stringEnum("How well the student recalled/pronounced the segment.", values: ["again", "good", "easy"])], required: ["grade"])
        ),
    ]

    /// Grammar session (Daily Pathway stage 2, between Vocab and Reading & Listening). Same rule
    /// as vocab/reading: navigation through today's grammar steps (usage points, conjugation
    /// tables, drills) is entirely app-driven; the model gets exactly one judgment-only tool for
    /// grading a drill answer, never a tool to advance/reveal content on its own initiative.
    static let grammarPalette: [AgentTool] = [
        AgentTool(
            name: "mark_drill_result",
            description: "Record whether the student's spoken answer to the current drill was correct. The app will only accept this if the student has actually attempted an answer.",
            parameters: object(["correct": ["type": "BOOLEAN", "description": "Whether the student's answer was correct."]], required: ["correct"])
        ),
    ]
}
