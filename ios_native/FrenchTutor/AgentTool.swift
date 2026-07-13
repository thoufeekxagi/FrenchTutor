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

    /// Listening + grammar session (Daily Pathway stage 2). Reading and listening are grouped
    /// together (TEF prep convention), and today's grammar focus is woven in as a natural aside
    /// rather than a fully separate stage.
    static let listeningPalette: [AgentTool] = [
        AgentTool(
            name: "show_conjugation",
            description: "Highlight a specific verb's conjugation table on the student's screen while you walk through it.",
            parameters: object(["verb": ["type": "STRING", "description": "The infinitive of the verb to highlight, exactly as it appears in the lesson context."]], required: ["verb"])
        ),
        AgentTool(
            name: "ask_drill",
            description: "Display a specific practice drill (fill-in-the-blank question with choices) from today's grammar lesson so the student can answer by tapping or saying the answer aloud.",
            parameters: object(["index": ["type": "INTEGER", "description": "Zero-based index of the drill in today's grammar lesson's drill list."]], required: ["index"])
        ),
        AgentTool(
            name: "grade_drill",
            description: "Record whether the student's answer to a displayed drill was correct.",
            parameters: object([
                "index": ["type": "INTEGER", "description": "Zero-based index of the drill."],
                "correct": ["type": "BOOLEAN", "description": "Whether the student's answer was correct."]
            ], required: ["index", "correct"])
        ),
        AgentTool(
            name: "show_question",
            description: "Display a listening comprehension question with its multiple-choice options after you've spoken the passage aloud.",
            parameters: object([
                "question": ["type": "STRING", "description": "The comprehension question text."],
                "choices": ["type": "ARRAY", "items": ["type": "STRING"], "description": "The answer choices."]
            ], required: ["question", "choices"])
        ),
        AgentTool(
            name: "mark_answer",
            description: "Record the student's answer to the currently displayed listening question.",
            parameters: object([
                "choice_index": ["type": "INTEGER", "description": "Zero-based index of the choice the student picked."],
                "correct": ["type": "BOOLEAN", "description": "Whether that choice was correct."]
            ], required: ["choice_index", "correct"])
        ),
    ]
}
