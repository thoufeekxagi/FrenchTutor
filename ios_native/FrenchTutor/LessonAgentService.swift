import Foundation

/// The "brain" behind lesson labs: answers questions, grades writing, explains
/// wrong quiz answers — all via OpenRouter free-tier text models. Voice (TTS/STT)
/// is handled separately by LessonSpeechService; this service is text-only.
final class LessonAgentService {
    static let shared = LessonAgentService()
    private init() {}

    /// Single fixed model, no fallback chain — MVP keeps this simple. Picked by live
    /// head-to-head testing against the other free-tier candidates on the app's actual
    /// prompt shapes: fastest turnaround (~3-4s vs. 8-13s) and the only one that returned
    /// clean JSON with no stray leading/trailing whitespace to strip.
    /// Overridable from Settings via UserDefaults key "openrouter_model_override".
    private var model: String {
        if let override = UserDefaults.standard.string(forKey: "openrouter_model_override"),
           !override.isEmpty {
            return override
        }
        return "nvidia/nemotron-3-super-120b-a12b:free"
    }

    enum AgentError: Error, LocalizedError {
        case missingKey
        case requestFailed
        case badResponse
        case badJSON(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "AI feedback unavailable — add an OpenRouter key in Settings."
            case .requestFailed: return "The AI tutor is busy right now. Try again in a moment."
            case .badResponse: return "The AI tutor gave an unexpected response."
            case .badJSON(let raw): return "LLM returned non-JSON: \(String(raw.prefix(200)))"
            }
        }
    }

    static func extractJSON(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences: ```json ... ``` or ``` ... ```
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        if let start = s.firstIndex(of: "["), let end = s.lastIndex(of: "]") {
            return String(s[start...end])
        }
        return s
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

    struct MicroWritingFeedback {
        let scoreOutOf10: Double
        let comment: String
    }

    struct MistakeJudgment {
        let isCorrect: Bool
        let tag: String?
        let description: String?
    }

    /// Runs invisibly alongside a live vocab session — takes what the student was asked to say
    /// and what speech recognition captured, and judges whether it was a reasonable attempt.
    /// Never shown to the user directly; only feeds the mistake ledger. Fire-and-forget by
    /// design: callers should swallow errors rather than surface them, since this is a nice-to-have
    /// enrichment, not part of the live conversation loop.
    func judgePronunciationAttempt(targetWord: String, studentSaid: String) async throws -> MistakeJudgment {
        // Kept as short as possible — this call fires on nearly every turn of a live session,
        // so its fixed cost multiplies fast; every token trimmed here is the single biggest
        // lever on this service's total token spend.
        let system = """
        Silently audit a French pronunciation attempt (student never sees this). They were asked \
        to say a French word aloud; below is what speech recognition captured (imperfect — be \
        lenient on transcription noise, but flag real errors: wrong verb form, confused similar \
        word, wrong word, silence). Reply with ONLY compact JSON, no markdown, no commentary: \
        {"correct": boolean, "tag": string_or_null, "description": string_or_null}. tag = short \
        stable snake_case slug for the error type (e.g. "nasal_vowel_confusion"), reused across \
        words so it can be tracked over time. Both null when correct is true.
        """
        let user = "TARGET WORD: \(targetWord)\nSPEECH RECOGNITION CAPTURED: \(studentSaid)"
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
        return try parseMistakeJudgment(raw)
    }

    struct SessionPlan {
        let focusNote: String
        let prioritizedWordIds: [String]?
    }

    /// Runs once, briefly, before a vocab session starts — looks at recurring mistakes and
    /// recent session history and decides what's worth emphasizing today, instead of always
    /// presenting the same fixed order. Callers should treat this as best-effort: on failure,
    /// fall back to the original candidate order with no focus note, no user-visible error.
    func planVocabSession(candidateWords: [VocabEntry], mistakeTags: [(tag: String, description: String, count: Int)], recentDiary: [String]) async throws -> SessionPlan {
        let system = """
        You are quietly planning a French vocabulary practice session before it starts — the student \
        won't see this reasoning, only the short focus note you write. Given the candidate word list, \
        the student's recurring mistake patterns, and recent session notes, decide: (1) a one-sentence, \
        warm, specific focus note for how today's session should be framed (e.g. referencing a specific \
        recurring mistake if relevant), and (2) optionally reorder the word IDs to front-load anything \
        especially relevant to their recent struggles — or return null to keep the given order if no \
        reordering is warranted. Respond with ONLY a compact JSON object: \
        {"focus_note": string, "prioritized_word_ids": array_of_strings_or_null}. \
        The prioritized_word_ids, if provided, must be a permutation of the exact candidate IDs given — \
        never invent new ones.
        """
        let wordList = candidateWords.map { "\($0.id): \($0.fr) (\($0.en))" }.joined(separator: "; ")
        var user = "CANDIDATE WORDS: \(wordList)"
        if !mistakeTags.isEmpty {
            user += "\n\nRECURRING MISTAKES: " + mistakeTags.map { "\($0.description) (seen \($0.count)x)" }.joined(separator: "; ")
        }
        if !recentDiary.isEmpty {
            user += "\n\nRECENT SESSION NOTES: " + recentDiary.joined(separator: " | ")
        }
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
        return try parseSessionPlan(raw, validIds: Set(candidateWords.map { $0.id }))
    }

    struct GrammarSessionPlan {
        let chosenId: String
        let focusNote: String
    }

    /// Runs once, briefly, before a grammar session starts, when the student picks "Auto" in
    /// `GrammarPickerView` — looks at recurring mistakes and recent session history and picks
    /// ONE tense/topic from the candidate list to focus on today, exactly the same best-effort
    /// shape as `planVocabSession` (fall back to the first candidate, no focus note, on failure).
    func planGrammarSession(candidates: [(id: String, title: String)], mistakeTags: [(tag: String, description: String, count: Int)], recentDiary: [String]) async throws -> GrammarSessionPlan {
        let system = """
        You are quietly picking which ONE French grammar point a beginner should practice today — \
        the student won't see this reasoning, only the short focus note you write. Given the \
        candidate list of tenses/topics, the student's recurring mistake patterns, and recent \
        session notes, choose the single most useful one to practice right now (e.g. if their \
        mistakes suggest passé composé confusion, pick that), and write a one-sentence warm, \
        specific focus note for how today's session should be framed. If nothing stands out, pick \
        the first candidate. Respond with ONLY a compact JSON object: \
        {"chosen_id": string, "focus_note": string}. chosen_id MUST be exactly one of the candidate \
        IDs given — never invent a new one.
        """
        let list = candidates.map { "\($0.id): \($0.title)" }.joined(separator: "; ")
        var user = "CANDIDATES: \(list)"
        if !mistakeTags.isEmpty {
            user += "\n\nRECURRING MISTAKES: " + mistakeTags.map { "\($0.description) (seen \($0.count)x)" }.joined(separator: "; ")
        }
        if !recentDiary.isEmpty {
            user += "\n\nRECENT SESSION NOTES: " + recentDiary.joined(separator: " | ")
        }
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
        return try parseGrammarSessionPlan(raw, validIds: Set(candidates.map { $0.id }), fallbackId: candidates.first?.id ?? "")
    }

    struct VocabExample: Codable {
        let fr: String
        let en: String
    }

    /// Runs ONCE, right after the vocab stage ends, if the student picks "a short reading/
    /// listening session on the words I just practiced" — assembles a short French passage/
    /// dialogue that naturally reuses those words, broken into `ReadingSegment`s (word/phrase,
    /// meaning, one simple grammar note, one pronunciation tip). This is pre-generation, not live
    /// teaching: the result is cached and handed to `AgentLedListeningView` exactly like
    /// offline-authored content — the model is never called again during the teaching session
    /// itself. Grammar notes are intentionally kept simple (no conjugation tables, no advanced
    /// tense discussion) for this first version; a harder/dynamic-difficulty version is planned
    /// for later once this base pattern is proven out, same as vocab's example-sentence approach.
    func buildReadingPassageFromVocab(words: [VocabEntry]) async throws -> ReadingPassage {
        let system = """
        You are quietly assembling a short French reading/listening passage for a total beginner \
        preparing for TEF/TCF Canada, using ONLY the vocabulary words given below (plus basic \
        connecting words like articles, "et", "je", "est", etc. as needed for grammatical French) — \
        do not introduce unrelated advanced vocabulary. Write 4-8 short segments (a word or a very \
        short phrase each) that together form a simple, coherent short passage or dialogue when \
        read in order. Keep grammar SIMPLE: present tense, short sentences, no advanced conjugation \
        or subjunctive — this is intentionally basic for a first pass. Respond with ONLY a compact \
        JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape:
        {"title": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}, ...]}
        Each segment's "fr" must be the exact short phrase as it appears in the passage (in order, \
        so concatenating them with spaces reproduces the full passage), "en" its English meaning, \
        "grammar_note" one simple English sentence explaining why that word/word order is used, and \
        "pronunciation_tip" one simple English sentence with a pronunciation pointer.
        """
        let wordList = words.map { "\($0.fr) (\($0.en))" }.joined(separator: ", ")
        let user = "VOCABULARY WORDS TO REUSE: \(wordList)"
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ], maxTokens: 1400)
        return try parseReadingPassage(raw)
    }


    /// Runs ONCE, right after a tense/topic is chosen for the Grammar stage (see
    /// `GrammarPickerView`) — builds a short deck of `GrammarPracticeCard`s (one short French
    /// sentence in the chosen tense per card, its English meaning, and a one-line grammar note),
    /// reusing the vocabulary words the student just practiced in the Vocab stage wherever
    /// natural, and informed by that Vocab session's actual transcript (what they said, how it
    /// went) rather than teaching the tense in a vacuum. Pre-generation, not live teaching: the
    /// result is cached and handed to `AgentLedGrammarView` exactly like offline-authored content
    /// — mirrors `buildReadingPassageFromVocab`'s shape. Grammar is kept intentionally SIMPLE
    /// (present-tense-level clarity even for other tenses) for this first pass; a harder/dynamic-
    /// difficulty version is planned for later, same as vocab's and reading's approach.
    /// Kept deliberately lean — only the tense name, a handful of vocab words, and one short line
    /// of recent context go in, not a full transcript or the whole usage-notes list. A bigger
    /// prompt was adding real latency for no quality gain; this is the whole request now, so it's
    /// fast and there's nothing left to trim without losing the point of the feature.
    var lastRawResponse: String = ""

    func generateGrammarPracticeCards(tenseTitle: String, tenseUsage: [String], vocabWords: [String], recentVocabTranscript: String, count: Int = 6) async throws -> [GrammarPracticeCard] {
        let words = vocabWords.prefix(6)
        let wordList = words.isEmpty ? "" : " using words: " + words.joined(separator: ", ")
        let user = "\(count) beginner French sentences in \(tenseTitle)\(wordList). Pure JSON only: {\"cards\":[{\"fr\":\"...\",\"en\":\"...\",\"note\":\"...\"}]}"
        let raw = try await complete(messages: [
            ["role": "user", "content": user]
        ], maxTokens: 800)
        lastRawResponse = raw
        return try parseGrammarPracticeCards(raw)
    }

    /// A fast, lightweight grade for the Daily Pathway's writing stage — one or two sentences
    /// using specific target words, not a full TEF rubric essay grade like `gradeWriting`.
    func gradeMicroWriting(prompt: String, targetWords: [String], submission: String) async throws -> MicroWritingFeedback {
        let system = """
        You are a friendly French tutor grading a one-to-two sentence micro writing exercise. \
        Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, \
        matching exactly this shape: {"score_out_of_10": number, "comment": string}. The comment should \
        be one short encouraging sentence, spoken-style with no markdown, since it will be read aloud.
        """
        let user = """
        TASK: \(prompt)
        TARGET WORDS: \(targetWords.joined(separator: ", "))

        STUDENT SUBMISSION:
        \(submission)
        """
        let raw = try await complete(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ])
        return try parseMicroWritingFeedback(raw)
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

    private func complete(messages: [[String: String]], maxTokens: Int = 1024) async throws -> String {
        guard !openRouterApiKey.isEmpty else { throw AgentError.missingKey }
        return try await request(model: model, messages: messages, maxTokens: maxTokens)
    }

    private func request(model: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(openRouterApiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/frenchtutor-app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("FrenchTutor Passeport", forHTTPHeaderField: "X-Title")

        // Without an explicit cap, a large batch response (e.g. 25 example sentences in one
        // JSON array) can get cut off mid-object by the model's own default completion length,
        // producing invalid JSON that fails to parse entirely — silently dropping every example
        // in the whole session, not just the ones past the cutoff. Callers with bigger expected
        // outputs (batch generation) pass a larger explicit value.
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.4,
            "max_tokens": maxTokens
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AgentError.badResponse }

        if http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw AgentError.requestFailed
        }
        guard (200...299).contains(http.statusCode) else {
            throw AgentError.requestFailed
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
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
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

    private func parseMicroWritingFeedback(_ raw: String) throws -> MicroWritingFeedback {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let score = (obj["score_out_of_10"] as? Double) ?? Double(obj["score_out_of_10"] as? Int ?? 0)
        let comment = obj["comment"] as? String ?? ""
        return MicroWritingFeedback(scoreOutOf10: score, comment: comment)
    }

    private func parseMistakeJudgment(_ raw: String) throws -> MistakeJudgment {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let correct = obj["correct"] as? Bool ?? true
        return MistakeJudgment(isCorrect: correct, tag: obj["tag"] as? String, description: obj["description"] as? String)
    }

    private func parseReadingPassage(_ raw: String) throws -> ReadingPassage {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let title = obj["title"] as? String ?? "Reading passage"
        let segmentsRaw = obj["segments"] as? [[String: Any]] ?? []
        let segments = segmentsRaw.compactMap { seg -> ReadingSegment? in
            guard let fr = seg["fr"] as? String, !fr.isEmpty else { return nil }
            return ReadingSegment(
                fr: fr,
                en: seg["en"] as? String ?? "",
                grammarNote: seg["grammar_note"] as? String ?? "",
                pronunciationTip: seg["pronunciation_tip"] as? String ?? ""
            )
        }
        guard !segments.isEmpty else { throw AgentError.badResponse }
        let fullText = (obj["full_text"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? segments.map { $0.fr }.joined(separator: " ")
        return ReadingPassage(id: "generated-\(UUID().uuidString.prefix(8))", title: title, segments: segments, fullText: fullText)
    }

    private func parseGrammarPracticeCards(_ raw: String) throws -> [GrammarPracticeCard] {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let cardsRaw = obj["cards"] as? [[String: Any]] ?? []
        let cards = cardsRaw.enumerated().compactMap { index, card -> GrammarPracticeCard? in
            guard let fr = card["fr"] as? String, !fr.isEmpty else { return nil }
            return GrammarPracticeCard(
                id: "generated-\(index)-\(UUID().uuidString.prefix(6))",
                fr: fr,
                en: card["en"] as? String ?? "",
                note: card["note"] as? String ?? ""
            )
        }
        guard !cards.isEmpty else { throw AgentError.badResponse }
        return cards
    }

    private func parseSessionPlan(_ raw: String, validIds: Set<String>) throws -> SessionPlan {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let focusNote = obj["focus_note"] as? String ?? ""
        var prioritized = obj["prioritized_word_ids"] as? [String]
        // Guard against a hallucinated/incomplete reordering — only trust it if it's an exact
        // permutation of the real candidate IDs, otherwise fall back to the given order.
        if let ids = prioritized, Set(ids) != validIds {
            prioritized = nil
        }
        return SessionPlan(focusNote: focusNote, prioritizedWordIds: prioritized)
    }

    private func parseGrammarSessionPlan(_ raw: String, validIds: Set<String>, fallbackId: String) throws -> GrammarSessionPlan {
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.badJSON(raw)
        }
        let focusNote = obj["focus_note"] as? String ?? ""
        let chosenId = obj["chosen_id"] as? String
        // Guard against a hallucinated ID the same way vocab guards a hallucinated reordering.
        let validChosenId = (chosenId.map { validIds.contains($0) } == true) ? chosenId! : fallbackId
        return GrammarSessionPlan(chosenId: validChosenId, focusNote: focusNote)
    }

}
