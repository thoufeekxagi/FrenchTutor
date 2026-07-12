import Foundation

/// The "brain" behind lesson labs: answers questions, grades writing, explains
/// wrong quiz answers — all via OpenRouter free-tier text models. Voice (TTS/STT)
/// is handled separately by LessonSpeechService; this service is text-only.
final class LessonAgentService {
    static let shared = LessonAgentService()
    private init() {}

    /// Tried in order; advances on 429 / 5xx / "no endpoints found" style errors.
    /// Overridable from Settings via UserDefaults key "openrouter_model_override".
    private let fallbackModels = [
        "meta-llama/llama-3.3-70b-instruct:free",
        "google/gemma-3-27b-it:free",
        "mistralai/mistral-small-3.1-24b-instruct:free"
    ]

    private var modelsToTry: [String] {
        if let override = UserDefaults.standard.string(forKey: "openrouter_model_override"),
           !override.isEmpty {
            return [override] + fallbackModels.filter { $0 != override }
        }
        return fallbackModels
    }

    enum AgentError: Error, LocalizedError {
        case missingKey
        case allModelsFailed
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: return "AI feedback unavailable — add an OpenRouter key in Settings."
            case .allModelsFailed: return "The AI tutor is busy right now. Try again in a moment."
            case .badResponse: return "The AI tutor gave an unexpected response."
            }
        }
    }

    // MARK: - Public API

    /// Bilingual tutor persona; answers are meant to be spoken aloud, so no markdown, ≤120 words.
    func askQuestion(lessonContext: String, question: String, history: [(role: String, text: String)] = []) async throws -> String {
        let system = """
        You are a friendly, encouraging bilingual (English/French) French tutor helping a student \
        preparing for the TEF/TCF Canada exam (target CLB 7). The student is mid-lesson; use the \
        LESSON CONTEXT to ground your answer. Keep answers under 120 words, spoken-style — no \
        markdown, no bullet lists, no asterisks, since your reply will be read aloud by a speech \
        synthesizer. Answer in English unless the student asks in French or asks for a French example.
        """
        var messages: [[String: String]] = [["role": "system", "content": system + "\n\nLESSON CONTEXT:\n" + lessonContext]]
        for turn in history {
            messages.append(["role": turn.role == "user" ? "user" : "assistant", "content": turn.text])
        }
        messages.append(["role": "user", "content": question])
        return try await complete(messages: messages)
    }

    struct WritingFeedback {
        let scoreOutOf10: Double
        let strengths: [String]
        let corrections: [(original: String, fixed: String, why: String)]
        let connectorFeedback: String
        let improvedVersion: String
    }

    func gradeWriting(task: WritingTask, submission: String) async throws -> WritingFeedback {
        let system = """
        You are a strict but encouraging TEF Canada writing examiner. Grade the student's submission \
        against the task using a TEF-style rubric (task completion, grammar/conjugation accuracy, \
        vocabulary range, use of logical connectors, coherence). Respond with ONLY a compact JSON object, \
        no markdown fences, no commentary outside the JSON, matching exactly this shape:
        {"score_out_of_10": number, "strengths": [string,...], "corrections": [{"original": string, "fixed": string, "why": string}, ...], "connector_feedback": string, "improved_version": string}
        """
        let user = """
        TASK: \(task.title)
        PROMPT: \(task.promptFr)
        MINIMUM WORDS: \(task.minWords)
        TARGET CONNECTORS: \(task.targetConnectors.joined(separator: ", "))

        STUDENT SUBMISSION:
        \(submission)
        """
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
        return try parseWritingFeedback(raw)
    }

    func checkDictation(expected: String, submitted: String) async throws -> String {
        let system = """
        You are a French dictation checker. Compare the EXPECTED sentence to the STUDENT'S TYPED version. \
        In under 60 words, spoken-style with no markdown, tell the student what they got right and point out \
        any missed accents, silent letters, or misheard words.
        """
        let user = "EXPECTED: \(expected)\nSTUDENT WROTE: \(submitted)"
        return try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
    }

    func quizFeedback(question: String, correctAnswer: String, studentAnswer: String, lessonContext: String) async throws -> String {
        let system = """
        You are a French grammar tutor. The student answered a drill question incorrectly. In under 80 \
        words, spoken-style with no markdown, explain why the correct answer is right and why their answer \
        was wrong, using the LESSON CONTEXT for grounding.
        """
        let user = "LESSON CONTEXT:\n\(lessonContext)\n\nQUESTION: \(question)\nCORRECT ANSWER: \(correctAnswer)\nSTUDENT ANSWER: \(studentAnswer)"
        return try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
    }

    // MARK: - Networking

    private func complete(messages: [[String: String]]) async throws -> String {
        guard !openRouterApiKey.isEmpty else { throw AgentError.missingKey }

        var lastError: Error = AgentError.allModelsFailed
        for model in modelsToTry {
            do {
                return try await request(model: model, messages: messages)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func request(model: String, messages: [[String: String]]) async throws -> String {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(openRouterApiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/frenchtutor-app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("FrenchTutor Passeport", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.4
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AgentError.badResponse }

        if http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw AgentError.allModelsFailed
        }
        guard (200...299).contains(http.statusCode) else {
            throw AgentError.allModelsFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw AgentError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseWritingFeedback(_ raw: String) throws -> WritingFeedback {
        var jsonString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = jsonString.firstIndex(of: "{"), let end = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[start...end])
        }
        guard let data = jsonString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badResponse
        }
        let score = (obj["score_out_of_10"] as? Double) ?? Double(obj["score_out_of_10"] as? Int ?? 0)
        let strengths = obj["strengths"] as? [String] ?? []
        let correctionsRaw = obj["corrections"] as? [[String: Any]] ?? []
        let corrections = correctionsRaw.map {
            (original: $0["original"] as? String ?? "",
             fixed: $0["fixed"] as? String ?? "",
             why: $0["why"] as? String ?? "")
        }
        let connectorFeedback = obj["connector_feedback"] as? String ?? ""
        let improved = obj["improved_version"] as? String ?? ""
        return WritingFeedback(
            scoreOutOf10: score,
            strengths: strengths,
            corrections: corrections,
            connectorFeedback: connectorFeedback,
            improvedVersion: improved
        )
    }
}
