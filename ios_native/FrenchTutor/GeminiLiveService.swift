import Foundation

class GeminiLiveService: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let apiKey: String
    private let model = "models/gemini-3.1-flash-live-preview"
    private let voiceName = "Puck"

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((String) -> Void)?
    var onUserTranscript: ((String) -> Void)?
    var onTutorTranscript: ((String) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    /// Fires when the model calls one of the declared `tools`. `callId` must be echoed back
    /// via `sendToolResponse`. Never fires when `tools` is empty (the default) — existing
    /// "Discuss with Marie" call sites are unaffected.
    var onToolCall: ((_ name: String, _ args: [String: Any], _ callId: String) -> Void)?
    /// Fires with each incremental chunk of her spoken output transcript AS IT STREAMS —
    /// word-by-word, in lockstep with the audio, since both come from the same generation
    /// pass. This is a much more reliable sync signal than tool-call timing: watching for a
    /// target word appearing here means "she is saying this right now," not "she decided to
    /// tell us about it" (which can arrive early, late, or not at all).
    var onTranscriptDelta: ((String) -> Void)?

    private var isSetupComplete = false
    private var currentUserTranscript = ""
    private var currentTutorTranscript = ""
    private var isIntentionalDisconnect = false
    private let lessonContext: String?
    private let tools: [AgentTool]

    static let systemPrompt = """
You are Marie, a warm, encouraging French tutor speaking to a student on a phone call. The \
student is working toward CLB 7 on the TEF/TCF Canada exam over a 6-month study plan — they are \
NOT necessarily a complete beginner, so calibrate your level from the STUDENT PROFILE you're given \
below rather than assuming. A student early in the plan needs slow, simple French with lots of \
English scaffolding; a student further along should be pushed with faster French, tougher \
vocabulary, and less hand-holding. Re-calibrate every call using the profile, don't default to \
"beginner mode" out of habit.

CRITICAL RULES — FOLLOW EXACTLY:
1. Reply ONLY as if you are talking to the student. Never describe your plan, your thoughts, or what you are about to do. Never say "I will" or "My aim is" or "I realize".
2. Match your pace to the student's level (see profile): slow and simple for someone early on; natural conversational speed for someone with more vocabulary/grammar under their belt.
3. Keep every reply short: one to three sentences max. This is a voice call, not a lecture.
4. You are fully bilingual and switch fluidly based on what the student needs:
   - If the student speaks or asks in English (e.g. asking for clarification, grammar help, or says they're confused), answer clearly in English first, then give the French equivalent.
   - If the student speaks in French, respond mostly in French, softly correcting mistakes by saying the correct French naturally, without lecturing.
   - Always let the student's own language choice guide you — never force French if they are clearly asking a question in English.
5. Ask one simple follow-up question at a time so the student keeps talking. Favor realistic, exam-relevant scenarios (roleplay a phone call, an opinion question, comparing two choices) over generic small talk once the profile shows they're past the basics.
6. No markdown, no bullet points, no asterisks, no headers, no numbered lists. Just plain natural speech.
7. If a LESSON CONTEXT block is provided below, that is what the student just studied or is currently working on — steer the conversation to practice exactly that material, using real-world use cases (not a dry recap).
8. Be encouraging and patient. Use short warm fillers like "très bien", "parfait", "doucement", "pas de souci" — or push a little harder ("essayons quelque chose de plus difficile") once the student is ready.

EXAMPLE OF A GOOD REPLY (student spoke French):
"Très bien! On dit... 'je m'appelle'. Tu peux essayer de le dire?"

EXAMPLE OF A GOOD REPLY (student asked in English):
"Sure! 'My name is' in French is 'je m'appelle'. Want to try saying it?"

EXAMPLE OF A BAD REPLY (NEVER DO THIS):
"I will now focus on greetings. My aim is to teach 'bonjour' and 'salut'. First, I will explain..."

START THE CALL WITH A WARM GREETING PITCHED AT THE STUDENT'S LEVEL FROM THE PROFILE. If a LESSON \
CONTEXT is provided, jump straight into practicing that material instead of a generic greeting.
"""

    init(apiKey: String, lessonContext: String? = nil, tools: [AgentTool] = []) {
        self.apiKey = apiKey
        self.lessonContext = lessonContext
        self.tools = tools
        self.session = URLSession(configuration: .default)
        super.init()
    }

    func connect() {
        isIntentionalDisconnect = false
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            onError?("Invalid API key or URL")
            return
        }

        task = session.webSocketTask(with: url)
        task?.resume()
        sendSetup()
        receiveMessages()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isSetupComplete = false
    }

    private var sentChunkCount = 0

    func sendAudioChunk(_ pcmData: Data) {
        guard isSetupComplete else {
            print("GeminiLiveService: dropping audio chunk, setup not complete")
            return
        }
        sentChunkCount += 1
        if sentChunkCount == 1 || sentChunkCount % 10 == 0 {
            print("GeminiLiveService: sent \(sentChunkCount) audio chunks, last size=\(pcmData.count)")
        }
        let b64 = pcmData.base64EncodedString()
        let msg: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": b64
                ]
            ]
        ]
        send(msg)
    }

    func sendText(_ text: String) {
        guard isSetupComplete else { return }
        let msg: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": text]]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        send(msg)
    }

    private var fullSystemPrompt: String {
        var prompt = GeminiLiveService.systemPrompt
        let profile = learnerProfile()
        if !profile.isEmpty {
            prompt += "\n\nSTUDENT PROFILE — use this to calibrate level and pacing; never read it aloud:\n" + profile
        }
        if let lessonContext, !lessonContext.isEmpty {
            prompt += "\n\nLESSON CONTEXT — the student is currently studying this material; steer practice toward it while following ALL rules above:\n" + lessonContext
        }
        return prompt
    }

    private func learnerProfile() -> String {
        ProgressService(store: LearningStore()).learnerProfileSummary()
    }

    /// Sends a context note mid-call so Marie can be redirected toward a new topic without
    /// ending the conversation. By default it's silent — she absorbs it and doesn't reply.
    /// With `expectReply: true` the note is framed as something to react to out loud NOW and
    /// the turn is closed so she actually generates a response — used for card changes, where
    /// she should announce what's newly on screen ("now the word is…") instead of going quiet
    /// or, worse, finishing a sentence about a card that's no longer there.
    func injectContext(_ note: String, expectReply: Bool = false) {
        guard isSetupComplete, !note.isEmpty else { return }
        let framed: String
        if expectReply {
            framed = "(Note from the app, not the student — the on-screen card just changed and " +
                "your audio may have been cut off mid-sentence. Do NOT finish or refer back to " +
                "your previous thought. React to this note now, briefly: ) \(note)"
        } else {
            framed = "(Note de contexte silencieuse pour toi, Marie — ne réponds pas directement à ceci, utilise-le seulement pour orienter la suite de la conversation) : \(note)"
        }
        let msg: [String: Any] = [
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": framed]]]],
                "turnComplete": expectReply
            ]
        ]
        send(msg)
    }

    private func sendSetup() {
        var generationConfig: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": voiceName
                    ]
                ]
            ]
        ]
        // Structured, tool-driven sessions (vocab/listening choreography) need disciplined
        // instruction-following far more than they need creative variety — lower temperature
        // measurably improves that. Freeform "Discuss with Marie" calls (no tools) keep the
        // default so that experience stays exactly as natural/varied as it's always been.
        if !tools.isEmpty {
            generationConfig["temperature"] = 0.65
        }
        var setupBody: [String: Any] = [
            "model": model,
            "generationConfig": generationConfig,
            "systemInstruction": [
                "parts": [["text": fullSystemPrompt]]
            ],
            "outputAudioTranscription": [:],
            "inputAudioTranscription": [:],
            "realtimeInputConfig": [
                "automaticActivityDetection": [
                    "disabled": false,
                    "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                    "prefixPaddingMs": 300,
                    "silenceDurationMs": 2500
                ]
            ]
        ]
        if !tools.isEmpty {
            setupBody["tools"] = [["functionDeclarations": tools.map { $0.declaration }]]
        }
        send(["setup": setupBody])
    }

    /// Answers a tool call the model made via `onToolCall`. Must be sent for every call,
    /// even ones that are pure UI updates, so the model knows to continue.
    /// `scheduling` controls how she incorporates the result: "SILENT" absorbs it without
    /// generating a reaction or interrupting her current flow (use for pure bookkeeping calls
    /// like grading/advancing, where a spoken acknowledgment of "the tool ran" would be
    /// unnatural filler) — vs. leaving it nil for calls whose result should shape what she
    /// says next. Other values: "WHEN_IDLE", "INTERRUPT".
    func sendToolResponse(callId: String, name: String, result: [String: Any], scheduling: String? = nil) {
        var response = result
        if let scheduling { response["scheduling"] = scheduling }
        let msg: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    ["id": callId, "name": name, "response": response]
                ]
            ]
        ]
        send(msg)
    }

    private var pendingMessages: [String] = []
    private var isSendingMessage = false
    private let sendQueueLock = NSLock()
    private let maxQueuedAudioMessages = 10

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        enqueueMessage(str)
    }

    private func enqueueMessage(_ message: String) {
        sendQueueLock.lock()
        pendingMessages.append(message)
        if pendingMessages.count > maxQueuedAudioMessages {
            pendingMessages.removeFirst(pendingMessages.count - maxQueuedAudioMessages)
        }
        let shouldStart = !isSendingMessage
        if shouldStart { isSendingMessage = true }
        sendQueueLock.unlock()

        if shouldStart {
            sendNextMessage()
        }
    }

    private func sendNextMessage() {
        sendQueueLock.lock()
        guard !pendingMessages.isEmpty else {
            isSendingMessage = false
            sendQueueLock.unlock()
            return
        }
        let message = pendingMessages.removeFirst()
        sendQueueLock.unlock()

        task?.send(.string(message)) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("GeminiLiveService: send error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onError?("Send error: \(error.localizedDescription)")
                }
            }
            self.sendNextMessage()
        }
    }

    private func receiveMessages() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()
            case .failure(let error):
                let closeCode = self.task?.closeCode.rawValue ?? -1
                let reason = self.task?.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("GeminiLiveService: connection failed: \(error.localizedDescription) closeCode=\(closeCode) reason=\(reason)")
                let wasIntentional = self.isIntentionalDisconnect
                DispatchQueue.main.async {
                    self.isSetupComplete = false
                    if !wasIntentional {
                        self.onError?("Connection closed: \(reason.isEmpty ? error.localizedDescription : reason)")
                    }
                    self.onDisconnected?()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        print("GeminiLiveService received keys: \(json.keys.sorted())")

        if let errorObj = json["error"] as? [String: Any] {
            let message = errorObj["message"] as? String ?? "Unknown error"
            DispatchQueue.main.async { self.onError?(message) }
            return
        }

        if json["setupComplete"] != nil {
            isSetupComplete = true
            DispatchQueue.main.async { self.onConnected?() }
            return
        }

        if let toolCall = json["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in calls {
                guard let name = call["name"] as? String, let id = call["id"] as? String else { continue }
                let args = call["args"] as? [String: Any] ?? [:]
                DispatchQueue.main.async { self.onToolCall?(name, args, id) }
            }
            return
        }

        guard let serverContent = json["serverContent"] as? [String: Any] else { return }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            if !currentTutorTranscript.isEmpty {
                let tutorTranscript = currentTutorTranscript
                currentTutorTranscript = ""
                DispatchQueue.main.async { self.onTutorTranscript?(tutorTranscript) }
            }
            DispatchQueue.main.async { self.onInterrupted?() }
            return
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String, !text.isEmpty {
            currentUserTranscript += text
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String, !text.isEmpty {
            DispatchQueue.main.async { self.onTranscriptDelta?(text) }
            if !currentUserTranscript.isEmpty {
                let userTranscript = currentUserTranscript
                currentUserTranscript = ""
                DispatchQueue.main.async { self.onUserTranscript?(userTranscript) }
            }
            currentTutorTranscript += text
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let audioB64 = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: audioB64) {
                    DispatchQueue.main.async { self.onAudioChunk?(audioData) }
                }
            }
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            if !currentUserTranscript.isEmpty {
                let userTranscript = currentUserTranscript
                currentUserTranscript = ""
                DispatchQueue.main.async { self.onUserTranscript?(userTranscript) }
            }
            if !currentTutorTranscript.isEmpty {
                let tutorTranscript = currentTutorTranscript
                currentTutorTranscript = ""
                DispatchQueue.main.async { self.onTutorTranscript?(tutorTranscript) }
            }
            DispatchQueue.main.async { self.onTurnComplete?() }
        }
    }
}
